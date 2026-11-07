import Foundation
import Testing
@testable import BatonCore

private let A = ClaudeFixture.a
private let B = ClaudeFixture.b
private let C = ClaudeFixture.c
private let D = "dddddddd-0000-4000-8000-000000000004"

/// Stands in for the CLI's Keychain item.
final class FakeCLICredentials: CLICredentialStore, @unchecked Sendable {
    let item = Locked<Data?>(nil)
    func read() throws -> Data? { item.get() }
    func write(_ data: Data) throws { item.set(data) }
}

/// Stands in for Claude Desktop Baton's own Keychain items.
final class MemorySecrets: SecretStore, @unchecked Sendable {
    let items = Locked<[String: Data]>([:])
    func load(_ key: String) -> Data? { items.get()[key] }
    func save(_ key: String, _ data: Data) throws { var all = items.get(); all[key] = data; items.set(all) }
    func delete(_ key: String) { var all = items.get(); all[key] = nil; items.set(all) }
    func keys() -> Set<String> { Set(items.get().keys) }
}

/// A Claude Desktop fixture plus a default CLI config: `~/.claude`, `~/.claude.json` and its Keychain item.
final class CLIFixture {
    let f: ClaudeFixture
    let paths: CLIPaths
    let credentials = FakeCLICredentials()
    let secrets = MemorySecrets()
    let cli: CLIAccounts

    init(signedIn: String? = ClaudeFixture.a, lockTimeout: TimeInterval = 2) throws {
        f = try ClaudeFixture(signedIn: signedIn)
        paths = CLIPaths(configHome: f.root.appendingPathComponent("home/.claude"),
                         globalConfig: f.root.appendingPathComponent("home/.claude.json"))
        try FileManager.default.createDirectory(at: paths.configHome, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["numStartups": 5, "projects": ["/code/x": ["allowedTools": []]]])
            .write(to: paths.globalConfig)
        cli = CLIAccounts(paths: paths, credentials: credentials, saved: secrets, store: f.store, lockTimeout: lockTimeout)
    }

    lazy var switcher = Switcher(claude: f.claude, paths: f.app, store: f.store, app: f.fake, timing: ClaudeFixture.fastTiming, cli: cli)

    /// Makes the CLI signed in to `account`, as `/login` would: its Keychain login and its account fields.
    func cliSignIn(_ account: String, token: String) throws {
        var item = (try? JSONSerialization.jsonObject(with: credentials.item.get() ?? Data())) as? [String: Any] ?? [:]
        item["mcpOAuth"] = item["mcpOAuth"] ?? ["server|1": ["accessToken": "mcp-keep"]]
        item["claudeAiOauth"] = ["accessToken": "cli-\(token)", "refreshToken": "rt-\(token)", "expiresAt": 1]
        credentials.item.set(try JSONSerialization.data(withJSONObject: item))
        var config = globalConfig
        config["oauthAccount"] = ["accountUuid": account, "organizationUuid": ClaudeFixture.org,
                                  "emailAddress": "\(account.prefix(4))@example.com"]
        try JSONSerialization.data(withJSONObject: config).write(to: paths.globalConfig)
    }

    var item: [String: Any] { (try? JSONSerialization.jsonObject(with: credentials.item.get() ?? Data())) as? [String: Any] ?? [:] }
    var cliRefreshToken: String? { (item["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String }
    var globalConfig: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.globalConfig))) as? [String: Any] ?? [:]
    }
    var cliAccount: String? { (globalConfig["oauthAccount"] as? [String: Any])?["accountUuid"] as? String }

    /// Desktop accounts A and B saved, each with a CLI sign-in; Claude and the CLI are on A.
    static func twoAccountsWithCLI() throws -> (CLIFixture, SavedAccount, SavedAccount) {
        let x = try CLIFixture(signedIn: B)
        let b = try x.f.saveSignedIn()
        try x.cliSignIn(B, token: "B")
        x.cli.saveCurrent()
        try x.f.signIn(A, token: "tok-A")
        let a = try x.f.saveSignedIn()
        try x.cliSignIn(A, token: "A")
        x.cli.saveCurrent()
        return (x, a, b)
    }
}

@Suite("CLI follows the switch", .serialized)
struct CLISignInTests {

    // AC5
    @Test func aCLISignInForASavedAccountIsSavedWithoutAnyAction() throws {
        let x = try CLIFixture(signedIn: A)
        try x.f.saveSignedIn()
        try x.cliSignIn(A, token: "A")

        let savedFor = x.cli.saveCurrent()

        #expect(savedFor == A)
        #expect(x.cli.hasSavedSignIn(A))
        #expect(x.cli.current() == .account(Identity(account: A, org: ClaudeFixture.org)))
    }

    // AC5
    @Test func aCLISignInForAnUnsavedAccountIsNotKept() throws {
        let x = try CLIFixture(signedIn: A)
        try x.f.saveSignedIn()
        try x.cliSignIn(D, token: "D")

        #expect(x.cli.saveCurrent() == nil)
        #expect(x.cli.accountsWithSavedSignIn().isEmpty)
    }

    @Test func aCLIWithoutAnAccountIsSignedOut() throws {
        let x = try CLIFixture()

        #expect(x.cli.current() == .signedOut)
    }

    // AC1: the CLI's login and account fields move; its MCP tokens and other settings stay.
    @Test func switchingMovesTheCLIToTheTargetAndKeepsEverythingElse() async throws {
        let (x, _, b) = try CLIFixture.twoAccountsWithCLI()

        let result = await x.switcher.switchTo(b)

        #expect(result.error == nil)
        #expect(result.cli == .moved)
        #expect(x.cliRefreshToken == "rt-B")
        #expect(x.cliAccount == B)
        #expect(((x.item["mcpOAuth"] as? [String: Any])?["server|1"] as? [String: Any])?["accessToken"] as? String == "mcp-keep")
        #expect(x.globalConfig["numStartups"] as? Int == 5)
        #expect(x.globalConfig["projects"] != nil)
    }

    // AC3: a token the CLI rotated under A survives A → B → A.
    @Test func aTokenTheCLIRotatedIsKeptAcrossSwitches() async throws {
        let (x, a, b) = try CLIFixture.twoAccountsWithCLI()
        try x.cliSignIn(A, token: "A-rotated")

        _ = await x.switcher.switchTo(b)
        let back = await x.switcher.switchTo(a)

        #expect(back.cli == .moved)
        #expect(x.cliAccount == A)
        #expect(x.cliRefreshToken == "rt-A-rotated")
    }

    // AC4
    @Test func withoutASavedCLISignInTheCLIIsLeftAsItWas() async throws {
        let x = try CLIFixture(signedIn: B)
        let b = try x.f.saveSignedIn()
        try x.f.signIn(A, token: "tok-A")
        try x.f.saveSignedIn()
        try x.cliSignIn(A, token: "A")
        let itemBefore = x.credentials.item.get()
        let configBefore = try Data(contentsOf: x.paths.globalConfig)

        let result = await x.switcher.switchTo(b)

        #expect(result.error == nil)
        #expect(result.cli == .notSaved(cli: .account(Identity(account: A, org: ClaudeFixture.org))))
        #expect(x.credentials.item.get() == itemBefore)
        #expect(try Data(contentsOf: x.paths.globalConfig) == configBefore)
    }

    // AC6: a refresh in a running CLI is waited for, and a lock left by a dead CLI is taken over.
    @Test func aRefreshInProgressIsWaitedForAndAStaleLockIsTakenOver() throws {
        let (x, _, b) = try CLIFixture.twoAccountsWithCLI()
        let fm = FileManager.default
        try fm.createDirectory(at: x.paths.refreshLock, withIntermediateDirectories: false)
        try fm.createDirectory(at: x.paths.legacyRefreshLock, withIntermediateDirectories: false)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: x.paths.legacyRefreshLock.path)
        let refreshing = x.paths.refreshLock
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { try? fm.removeItem(at: refreshing) }

        let result = x.cli.follow(b)

        #expect(result == .moved)
        #expect(x.cliAccount == B)
        #expect(!fm.fileExists(atPath: x.paths.refreshLock.path))
        #expect(!fm.fileExists(atPath: x.paths.legacyRefreshLock.path))
        #expect(!fm.fileExists(atPath: x.paths.configLock.path))
    }

    // AC6 / review: a refresh that finishes while the switch waits for the lock is the one saved for A.
    @Test func aRefreshThatFinishesDuringTheWaitIsTheTokenSaved() async throws {
        let (x, a, b) = try CLIFixture.twoAccountsWithCLI()
        try FileManager.default.createDirectory(at: x.paths.refreshLock, withIntermediateDirectories: false)
        let lock = x.paths.refreshLock
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            try? x.cliSignIn(A, token: "A-rotated")
            try? FileManager.default.removeItem(at: lock)
        }

        #expect(x.cli.follow(b) == .moved)
        #expect(x.cli.follow(a) == .moved)

        #expect(x.cliRefreshToken == "rt-A-rotated")
    }

    // Review: an item that is not JSON must not be replaced by one holding only the login.
    @Test func anUnreadableCLIItemIsLeftAlone() throws {
        let (x, _, b) = try CLIFixture.twoAccountsWithCLI()
        let unreadable = Data("not json".utf8)
        x.credentials.item.set(unreadable)

        let result = x.cli.follow(b)

        guard case .failed = result else { Issue.record("expected a failure, got \(result)"); return }
        #expect(x.credentials.item.get() == unreadable)
        #expect(x.cliAccount == A)
    }

    // Review: `security -w` prints a value as hex when it holds bytes it deems unprintable.
    @Test func aHexPrintedItemIsReadAsItsJSON() {
        let json = Data(#"{"claudeAiOauth":{"refreshToken":"rt-é"}}"#.utf8)
        let hex = Data(json.map { String(format: "%02x", $0) }.joined().utf8)

        #expect(SecurityCLICredentials.decode(hex) == json)
        #expect(SecurityCLICredentials.decode(json) == json)
    }

    // AC6: a refresh that outlasts the wait leaves the CLI and its lock alone.
    @Test func aLockHeldPastTheWaitLeavesTheCLIUnchanged() throws {
        let (x, _, b) = try CLIFixture.twoAccountsWithCLI()
        let short = CLIAccounts(paths: x.paths, credentials: x.credentials, saved: x.secrets, store: x.f.store, lockTimeout: 0.3)
        try FileManager.default.createDirectory(at: x.paths.refreshLock, withIntermediateDirectories: false)
        let itemBefore = x.credentials.item.get()

        let result = short.follow(b)

        guard case .failed = result else { Issue.record("expected a failure, got \(result)"); return }
        #expect(x.credentials.item.get() == itemBefore)
        #expect(x.cliAccount == A)
        #expect(FileManager.default.fileExists(atPath: x.paths.refreshLock.path))
    }

    // AC7: the CLI moves only after Claude confirms the target.
    @Test func aFailedDesktopSwitchLeavesTheCLIUnchanged() async throws {
        let (x, _, b) = try CLIFixture.twoAccountsWithCLI()
        x.f.fake.loadsInstead = C

        let result = await x.switcher.switchTo(b)

        #expect(result.error != nil)
        #expect(result.cli == nil)
        #expect(x.cliAccount == A)
        #expect(x.cliRefreshToken == "rt-A")
    }

    // AC8
    @Test func removingAnAccountForgetsOnlyItsSavedCLISignIn() throws {
        let (x, _, _) = try CLIFixture.twoAccountsWithCLI()
        let configBefore = try Data(contentsOf: x.paths.globalConfig)

        x.cli.forget(A)

        #expect(!x.cli.hasSavedSignIn(A))
        #expect(x.cli.hasSavedSignIn(B))
        #expect(x.cliRefreshToken == "rt-A")
        #expect(try Data(contentsOf: x.paths.globalConfig) == configBefore)
    }

    // AC10
    @Test func noCLITokenIsWrittenToTheAppsFiles() async throws {
        let (x, a, b) = try CLIFixture.twoAccountsWithCLI()
        _ = await x.switcher.switchTo(b)
        _ = await x.switcher.switchTo(a)

        let files = FileManager.default.enumerator(at: x.f.app.root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        #expect(!files.isEmpty)
        for file in files {
            let text = String(decoding: (try? Data(contentsOf: file)) ?? Data(), as: UTF8.self)
            #expect(!text.contains("rt-") && !text.contains("cli-"), "\(file.lastPathComponent)")
        }
    }

    // MARK: panel

    // AC5: the panel tags the CLI's account and says which accounts have no CLI sign-in yet.
    @Test func thePanelTagsTheCLIAccount() throws {
        let (x, _, _) = try CLIFixture.twoAccountsWithCLI()
        let accounts = x.f.store.all()
        let onB = PanelState.make(accounts: accounts, current: nil, usage: [:], phase: .idle, now: Date(),
                                  cli: .account(Identity(account: B, org: ClaudeFixture.org)), cliSaved: [B])
        let signedOut = PanelState.make(accounts: accounts, current: nil, usage: [:], phase: .idle, now: Date(),
                                        cli: .signedOut, cliSaved: [A, B])
        let elsewhere = PanelState.make(accounts: accounts, current: nil, usage: [:], phase: .idle, now: Date(),
                                        cli: .account(Identity(account: D, org: ClaudeFixture.org)), cliSaved: [A, B])

        #expect(onB.rows.filter(\.isCLI).map(\.id) == [B])
        #expect(onB.cliNote == nil)
        #expect(onB.rows.first { $0.id == A }?.tooltip.contains("CLI not signed in yet") == true)
        #expect(onB.rows.first { $0.id == B }?.tooltip.contains("CLI not signed in yet") == false)
        #expect(signedOut.rows.allSatisfy { !$0.isCLI })
        #expect(signedOut.cliNote == "CLI: signed out")
        #expect(elsewhere.cliNote == "CLI: not on a saved account")
    }

    @Test func theAlertNamesBothAccountsAndTheOneTimeSignIn() {
        let alert = Alerts.cliNotFollowing(to: "Work", cli: "Personal")
        let signedOut = Alerts.cliNotFollowing(to: "Work", cli: nil)

        #expect(alert.title == "Switched to Work")
        #expect(alert.message.contains("The CLI is still on Personal"))
        #expect(alert.message.contains("/login") && alert.message.contains("Work"))
        #expect(signedOut.message.contains("signed out"))
    }

    // MARK: command line

    // AC11: status and accounts report the CLI account and which accounts would move it; no credentials.
    @Test func theCommandLineReportsTheCLIAccount() async throws {
        let (x, _, _) = try CLIFixture.twoAccountsWithCLI()
        let reader = UsageReader(cache: UsageCache(file: x.f.app.usageCache),
                                 client: UsageClient(protocolClasses: [UsageStub.self], userAgent: "t", key: { Data(count: 16) }),
                                 claude: x.f.claude)
        let context = AgentContext(claude: x.f.claude, store: x.f.store, usage: reader, environment: [:],
                                   status: { StatusFacts(claudeRunning: true, menuBarAppRunning: true, workingSessions: 0,
                                                         legacyImportable: 0, syncPreview: "nothing") },
                                   requestSwitch: { _, _ in .success(.done(error: nil)) }, cli: x.cli)
        x.cli.forget(B)

        let accounts = await AgentCommand.run(["accounts", "--json"], context)
        let status = await AgentCommand.run(["status"], context)
        let statusJSON = await AgentCommand.run(["status", "--json"], context)

        let rows = (try JSONSerialization.jsonObject(with: Data(accounts.text.utf8)) as? [String: Any])?["accounts"] as? [[String: Any]] ?? []
        #expect(rows.first { $0["accountId"] as? String == A }?["cli"] as? Bool == true)
        #expect(rows.first { $0["accountId"] as? String == A }?["cliSignInSaved"] as? Bool == true)
        #expect(rows.first { $0["accountId"] as? String == B }?["cliSignInSaved"] as? Bool == false)
        #expect(status.text.contains("CLI: Acme"))
        let cli = (try JSONSerialization.jsonObject(with: Data(statusJSON.text.utf8)) as? [String: Any])?["cli"] as? [String: Any]
        #expect(cli?["accountId"] as? String == A)
        for text in [accounts.text, status.text, statusJSON.text] {
            #expect(!text.contains("rt-") && !text.contains("cli-A"))
        }
    }
}
