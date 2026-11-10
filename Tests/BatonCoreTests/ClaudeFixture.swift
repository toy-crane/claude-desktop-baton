import Foundation
import SQLite3
@testable import BatonCore

/// A throwaway Claude Desktop data folder: config.json, a Chromium-style Cookies database,
/// main.log and claude-code-sessions, plus Claude Desktop Baton's own folder.
final class ClaudeFixture {
    static let org = "0000000f-0000-4000-8000-00000000000f"
    static let a = "aaaaaaaa-0000-4000-8000-000000000001"
    static let b = "bbbbbbbb-0000-4000-8000-000000000002"
    static let c = "cccccccc-0000-4000-8000-000000000003"

    let root: URL
    let claude: ClaudePaths
    let app: AppPaths
    let store: AccountStore
    let fake: FakeClaude
    lazy var switcher = Switcher(claude: claude, paths: app, store: store, app: fake, timing: Self.fastTiming)

    static var fastTiming: SwitchTiming {
        var t = SwitchTiming()
        t.quitTimeout = .milliseconds(300)
        t.loadTimeout = .milliseconds(300)
        t.poll = .milliseconds(10)
        return t
    }

    init(signedIn account: String? = ClaudeFixture.a) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("baton-claude-\(UUID().uuidString)")
        let data = root.appendingPathComponent("Claude")
        claude = ClaudePaths(dataDir: data, log: root.appendingPathComponent("Logs/main.log"),
                             projects: root.appendingPathComponent("claude-projects"),
                             cliSessions: root.appendingPathComponent("claude-sessions"))
        app = AppPaths(root: root.appendingPathComponent("Baton"))
        store = AccountStore(paths: app)
        fake = FakeClaude(claude: claude)
        let fm = FileManager.default
        try fm.createDirectory(at: claude.sessionsRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: claude.log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: claude.log)
        try JSONSerialization.data(withJSONObject: ["darkMode": "system"]).write(to: claude.config)
        let db = try SQLite(claude.cookies, write: true, create: true)
        try db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
        try db.execute("INSERT INTO meta VALUES ('version', '24')")
        try db.execute("CREATE TABLE cookies (creation_utc INTEGER, host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER)")
        try db.execute("INSERT INTO cookies VALUES (13400000000000001, 'example.com', 'other', 'keep', X'', '/', 0)")
        for id in [Self.a, Self.b, Self.c] {
            try fm.createDirectory(at: claude.sessionsRoot.appendingPathComponent("\(id)/\(Self.org)"), withIntermediateDirectories: true)
        }
        if let account { try signIn(account, token: "tok-\(account.prefix(1))") }
        fake.running = true
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// Makes Claude's files look signed in to `account`, as if Claude had just loaded it.
    func signIn(_ account: String, token: String) throws {
        var config = try JSONSerialization.jsonObject(with: Data(contentsOf: claude.config)) as! [String: Any]
        config["oauth:tokenCacheV2"] = token
        config["lastKnownAccountUuid"] = account
        try JSONSerialization.data(withJSONObject: config).write(to: claude.config)
        let db = try SQLite(claude.cookies, write: true)
        try db.execute("DELETE FROM cookies WHERE host_key IN ('claude.ai','.claude.ai')")
        try db.execute("INSERT INTO cookies VALUES (13400000000000002, '.claude.ai', 'sessionKey', 'sk-\(account.prefix(1))', X'', '/', 0)")
        appendLog(account)
    }

    func appendLog(_ account: String) {
        let line = "[info] [LocalSessionManager] Initialization succeeded — accountId=\(account), orgId=\(Self.org)\n"
        let handle = try! FileHandle(forWritingTo: claude.log)
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try! handle.close()
    }

    /// Saves the account that is signed in now, as the app would.
    @discardableResult
    func saveSignedIn(email: String? = nil) throws -> SavedAccount {
        let signIn = try SignInStore.read(claude)
        let account = SavedAccount(accountId: signIn.accountId!, orgId: Self.org, email: email, orgName: "Acme",
                                   savedAt: Date().timeIntervalSince1970 * 1000, signIn: signIn)
        try store.save(account)
        return account
    }

    var configAccount: String? { (try? SignInStore.read(claude))?.accountId }
    var configToken: String? { (try? SignInStore.read(claude))?.config["oauth:tokenCacheV2"] }
    var config: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(contentsOf: claude.config))) as? [String: Any] ?? [:] }
    var sessionKey: String? { (try? SignInStore.read(claude))?.cookies.first { $0["name"]?.text == "sessionKey" }?["value"]?.text }
    var otherCookie: String? {
        (try? SQLite(claude.cookies, write: false).rows("SELECT value FROM cookies WHERE host_key='example.com'"))?.first?["value"]?.text
    }

    func folder(_ account: String) -> URL { claude.sessionsRoot.appendingPathComponent("\(account)/\(Self.org)") }

    func writeSession(_ account: String, _ uuid: String, secondsAgo: Double, archived: Bool = false, cliSessionId: String? = nil) throws {
        var body: [String: Any] = ["sessionId": "local_\(uuid)",
                                   "lastActivityAt": Int64((Date().timeIntervalSince1970 - secondsAgo) * 1000),
                                   "isArchived": archived]
        body["cliSessionId"] = cliSessionId
        try JSONSerialization.data(withJSONObject: body).write(to: folder(account).appendingPathComponent("local_\(uuid).json"))
    }

    /// A Claude Code conversation file, last written `secondsAgo`.
    func writeTranscript(_ cliSessionId: String, secondsAgo: Double) throws {
        let dir = claude.projects.appendingPathComponent("-Users-someone-code-project")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(cliSessionId).jsonl")
        try Data("{}\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: file.path)
    }

    func hasSession(_ account: String, _ uuid: String) -> Bool {
        FileManager.default.fileExists(atPath: folder(account).appendingPathComponent("local_\(uuid).json").path)
    }
}

/// Stands in for Claude Desktop: quitting stops it, and opening loads whatever sign-in is in place,
/// writing the same log line Claude writes.
final class FakeClaude: ClaudeApp, @unchecked Sendable {
    let claude: ClaudePaths
    var running = false
    var refusesToQuit = false
    /// Simulates an expired saved sign-in: Claude loads this account instead.
    var loadsInstead: String?
    var opened = 0
    /// Called when Claude opens, to observe what was in place at that moment.
    var onOpen: (() -> Void)?

    init(claude: ClaudePaths) { self.claude = claude }

    var isRunning: Bool { running }
    func quit() { if !refusesToQuit { running = false } }

    func open() async throws {
        running = true
        opened += 1
        onOpen?()
        guard let account = loadsInstead ?? (try? SignInStore.read(claude))?.accountId else { return }
        let line = "[info] [LocalSessionManager] Initialization succeeded — accountId=\(account), orgId=\(ClaudeFixture.org)\n"
        let handle = try FileHandle(forWritingTo: claude.log)
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try handle.close()
    }
}
