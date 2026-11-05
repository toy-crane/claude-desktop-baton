import Foundation

/// Where Claude Desktop keeps what this app reads and swaps. Undocumented; observed in Claude Desktop 2.16.
public struct ClaudePaths: Sendable {
    public let dataDir: URL
    public let log: URL
    /// Claude Code conversations, shared by every account: <project>/<cliSessionId>.jsonl.
    public let projects: URL

    public var config: URL { dataDir.appendingPathComponent("config.json") }
    public var cookies: URL { dataDir.appendingPathComponent("Cookies") }
    public var sessionsRoot: URL { dataDir.appendingPathComponent("claude-code-sessions") }

    public init(dataDir: URL, log: URL,
                projects: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.dataDir = dataDir
        self.log = log
        self.projects = projects
    }

    public static let live = ClaudePaths(
        dataDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude"),
        log: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Claude/main.log"))

    /// The folder Claude holds in memory for this account and organization.
    public func sessionFolder(_ identity: Identity) -> URL {
        sessionsRoot.appendingPathComponent(identity.account).appendingPathComponent(identity.org)
    }
}

/// Claude Desktop Baton's own files.
public struct AppPaths: Sendable {
    public let root: URL
    public var accountsDir: URL { root.appendingPathComponent("accounts") }
    public var previousSignIn: URL { root.appendingPathComponent("previous.json") }
    public var staging: URL { root.appendingPathComponent("staging") }
    public var trash: URL { root.appendingPathComponent("trash") }

    public init(root: URL) { self.root = root }

    public static let live = AppPaths(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude Desktop Baton"))
    /// Accounts saved by the reference project (claude-desktop-accounts), imported once.
    public static let legacyAccounts = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude Accounts/accounts")

    public func syncLocations(_ claude: ClaudePaths) -> SyncLocations {
        SyncLocations(sessionsRoot: claude.sessionsRoot, stagingDir: staging, trashDir: trash)
    }
}

public struct BatonError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

// MARK: identity

public struct Identity: Equatable, Sendable, Hashable {
    public let account: String
    public let org: String
    public init(account: String, org: String) { self.account = account; self.org = org }
}

/// Claude Desktop logs this line each time an account finishes loading its Code sessions.
public enum ClaudeLog {
    static let initLine = try! NSRegularExpression(
        pattern: #"\[LocalSessionManager\] Initialization succeeded — accountId=([0-9a-f-]{36}), orgId=([0-9a-f-]{36})"#)

    public static func lastIdentity(in text: String) -> Identity? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = initLine.matches(in: text, range: range).last,
              let account = Range(match.range(at: 1), in: text),
              let org = Range(match.range(at: 2), in: text) else { return nil }
        return Identity(account: String(text[account]), org: String(text[org]))
    }

    public static func size(_ log: URL) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: log.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// The account loaded after `offset`: used to confirm the account Claude opens after a relaunch.
    public static func identity(in log: URL, after offset: UInt64) -> Identity? {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return nil }
        return lastIdentity(in: String(decoding: data, as: UTF8.self))
    }

    /// The account Claude loaded most recently.
    public static func current(_ log: URL, tailBytes: UInt64 = 512 * 1024) -> Identity? {
        let size = size(log)
        if let found = identity(in: log, after: size > tailBytes ? size - tailBytes : 0) { return found }
        return size > tailBytes ? identity(in: log, after: 0) : nil
    }
}

// MARK: sign-in

/// One SQLite value, kept exactly. Integers as strings: cookie timestamps exceed 2^53.
/// The encoding matches the reference project's saved accounts so they import unchanged.
public enum CookieValue: Codable, Equatable, Sendable {
    case integer(String), real(String), text(String), blob(Data), null

    private enum Key: String, CodingKey { case i, r, s, b, n }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .i) { self = .integer(v) }
        else if let v = try c.decodeIfPresent(String.self, forKey: .r) { self = .real(v) }
        else if let v = try c.decodeIfPresent(String.self, forKey: .s) { self = .text(v) }
        else if let v = try c.decodeIfPresent(Data.self, forKey: .b) { self = .blob(v) }
        else { self = .null }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .integer(let v): try c.encode(v, forKey: .i)
        case .real(let v): try c.encode(v, forKey: .r)
        case .text(let v): try c.encode(v, forKey: .s)
        case .blob(let v): try c.encode(v, forKey: .b)
        case .null: try c.encode(true, forKey: .n)
        }
    }
    public var text: String? { if case .text(let v) = self { return v }; return nil }
    public var blob: Data? { if case .blob(let v) = self { return v }; return nil }
}

public typealias CookieRow = [String: CookieValue]

/// Everything that makes Claude Desktop signed in as one account, still encrypted as Claude stored it.
public struct SignIn: Codable, Equatable, Sendable {
    public static let configKeys = ["oauth:tokenCache", "oauth:tokenCacheV2", "lastKnownAccountUuid"]
    static let hosts = ["claude.ai", ".claude.ai"]

    public var config: [String: String]
    public var cookieSchema: Int
    public var cookies: [CookieRow]

    public init(config: [String: String], cookieSchema: Int, cookies: [CookieRow]) {
        self.config = config
        self.cookieSchema = cookieSchema
        self.cookies = cookies
    }

    public var accountId: String? { config["lastKnownAccountUuid"] }
    public var hasTokens: Bool { config["oauth:tokenCacheV2"] != nil || config["oauth:tokenCache"] != nil }
    public var hasSessionKey: Bool { cookies.contains { $0["name"]?.text == "sessionKey" } }

    /// An empty sign-in with the same cookie format: Claude opens signed out.
    public func signedOut() -> SignIn { SignIn(config: [:], cookieSchema: cookieSchema, cookies: []) }
}

/// Reads and replaces Claude's sign-in. Writes only while Claude is closed.
public enum SignInStore {
    public static func read(_ paths: ClaudePaths) throws -> SignIn {
        guard let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.config))) as? [String: Any] else {
            throw BatonError("Claude's settings file could not be read.")
        }
        let db = try SQLite(paths.cookies, write: false)
        let hosts = SignIn.hosts.map { "'\($0)'" }.joined(separator: ",")
        let cookies = try db.rows("SELECT * FROM cookies WHERE host_key IN (\(hosts)) ORDER BY host_key, name, path")
        return SignIn(config: config.compactMapValues { $0 as? String }.filter { SignIn.configKeys.contains($0.key) },
                      cookieSchema: try db.schemaVersion(), cookies: cookies)
    }

    /// Puts `replacement` in place: cookies in one transaction, then the three config entries.
    /// A config failure puts the previous cookies back.
    public static func replace(with replacement: SignIn, _ paths: ClaudePaths) throws {
        let current = try read(paths)
        try writeCookies(replacement, paths)
        do {
            try writeConfig(replacement.config, paths)
        } catch {
            try? writeCookies(current, paths)
            throw error
        }
    }

    static func writeCookies(_ signIn: SignIn, _ paths: ClaudePaths) throws {
        let db = try SQLite(paths.cookies, write: true)
        guard try db.schemaVersion() == signIn.cookieSchema else {
            throw BatonError("Claude changed its cookie format since this account was saved. Sign in to it again in Claude.")
        }
        let columns = Set(try db.rows("PRAGMA table_info(cookies)").compactMap { $0["name"]?.text })
        guard signIn.cookies.allSatisfy({ Set($0.keys).isSubset(of: columns) }) else {
            throw BatonError("Claude changed its cookie format since this account was saved. Sign in to it again in Claude.")
        }
        let hosts = SignIn.hosts.map { "'\($0)'" }.joined(separator: ",")
        try db.transaction {
            try db.execute("DELETE FROM cookies WHERE host_key IN (\(hosts))")
            for row in signIn.cookies { try db.insert(into: "cookies", row) }
        }
    }

    /// Replaces only the sign-in entries and keeps every other setting; written to a temp file and renamed.
    static func writeConfig(_ entries: [String: String], _ paths: ClaudePaths) throws {
        guard var config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.config))) as? [String: Any] else {
            throw BatonError("Claude's settings file could not be read.")
        }
        for key in SignIn.configKeys { config[key] = entries[key] }
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])
        let mode = (try? FileManager.default.attributesOfItem(atPath: paths.config.path))?[.posixPermissions] as? Int ?? 0o600
        let temp = paths.dataDir.appendingPathComponent(".config.json.\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: mode]) else {
            throw BatonError("Claude's settings file could not be written.")
        }
        guard Darwin.rename(temp.path, paths.config.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw BatonError("Claude's settings file could not be replaced.")
        }
    }
}
