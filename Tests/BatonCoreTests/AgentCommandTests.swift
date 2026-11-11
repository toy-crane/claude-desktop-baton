import Foundation
import Testing
@testable import BatonCore

private let A = ClaudeFixture.a
private let B = ClaudeFixture.b
private let C = ClaudeFixture.c

/// Answers usage requests for the command's tests and counts them. Separate from StubProtocol,
/// whose suite runs in parallel with this one.
final class UsageStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0
    static var count: Int {
        get { lock.lock(); defer { lock.unlock() }; return requests }
        set { lock.lock(); requests = newValue; lock.unlock() }
    }
    nonisolated(unsafe) static var body = Data(#"{"five_hour":{"utilization":8},"seven_day":{"utilization":34}}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Records what the command hands to the menu bar app and answers as told.
final class AppStandIn: @unchecked Sendable {
    var requests: [(request: ControlRequest, wait: Bool)] = []
    var answer: Result<ControlResponse, ControlError> = .success(.done(error: nil))
}

@Suite("Agent command line", .serialized)
struct AgentCommandTests {

    /// A signed in; A, B and C saved with emails.
    private func threeAccounts() throws -> ClaudeFixture {
        let f = try ClaudeFixture(signedIn: C)
        try f.saveSignedIn(email: "carol@example.com")
        usleep(3000) // the save order sets the panel order, in milliseconds
        try f.signIn(B, token: "tok-B")
        try f.saveSignedIn(email: "bob@example.com")
        usleep(3000)
        try f.signIn(A, token: "tok-A")
        try f.saveSignedIn(email: "alice@example.com")
        return f
    }

    private func reader(_ f: ClaudeFixture) -> UsageReader {
        UsageReader(cache: UsageCache(file: f.app.usageCache),
                    client: UsageClient(protocolClasses: [UsageStub.self], userAgent: "test", key: { Data(count: 16) }),
                    claude: f.claude)
    }

    private func context(_ f: ClaudeFixture, _ app: AppStandIn, environment: [String: String] = [:],
                         now: Date = Date()) -> AgentContext {
        AgentContext(claude: f.claude, store: f.store, usage: reader(f), environment: environment, now: { now },
                     status: { StatusFacts(claudeRunning: true, menuBarAppRunning: false, workingSessions: 0,
                                           legacyImportable: 0, syncPreview: "nothing to change") },
                     requestSwitch: { request, wait in app.requests.append((request, wait)); return app.answer })
    }

    private func json(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    private func usage(_ session: Double, _ week: Double) -> Usage {
        Usage(session: .init(used: session, resetsAt: nil), week: .init(used: week, resetsAt: nil))
    }

    private func cache(_ f: ClaudeFixture, _ values: [String: Usage], at date: Date) {
        let cache = UsageCache(file: f.app.usageCache)
        for (id, value) in values { cache.store(id, UsageSnapshot(usage: value, fetchedAt: date)) }
    }

    // MARK: accounts

    // AC11 (switch-to-order): every saved account in name order, the signed-in one marked.
    @Test func accountsListsEverySavedAccountInNameOrderAndMarksTheSignedInOne() async throws {
        let f = try threeAccounts()

        let out = await AgentCommand.run(["accounts", "--json"], context(f, AppStandIn()))

        let rows = json(out.text)["accounts"] as? [[String: Any]] ?? []
        #expect(out.code == 0)
        #expect(rows.map { $0["accountId"] as? String } == [A, B, C])
        #expect(rows.map { $0["signedIn"] as? Bool } == [true, false, false])
        #expect(rows.map { $0["email"] as? String } == ["alice@example.com", "bob@example.com", "carol@example.com"])
    }

    // MARK: choosing an account

    // AC10
    @Test func anAccountIsFoundByItsNameEmailOrIdPrefix() throws {
        let f = try threeAccounts()
        let accounts = f.store.all()

        for query in ["Acme · bob", "acme · BOB", "bob@example.com", "BOB@EXAMPLE.COM", "bbbbbbbb", "bbbb"] {
            guard case .found(let account) = AccountMatch.find(query, in: accounts) else {
                Issue.record("\(query) did not find bob"); continue
            }
            #expect(account.accountId == B)
        }
    }

    // AC10
    @Test func anUnknownAccountIsAnErrorThatListsTheCandidates() async throws {
        let f = try threeAccounts()
        let app = AppStandIn()

        let out = await AgentCommand.run(["switch", "dave"], context(f, app))

        #expect(out.code == 1)
        #expect(out.text.contains("Acme · alice") && out.text.contains("Acme · bob") && out.text.contains("Acme · carol"))
        #expect(app.requests.isEmpty)
    }

    // AC10: the same email in two organizations names two accounts.
    @Test func anAmbiguousAccountIsAnErrorThatListsTheMatches() throws {
        let f = try threeAccounts()
        var other = try #require(f.store.load(C))
        other.email = "bob@example.com"
        try f.store.save(other)

        guard case .ambiguous(let candidates) = AccountMatch.find("bob@example.com", in: f.store.all()) else {
            Issue.record("expected an ambiguous match"); return
        }
        #expect(candidates.count == 2)
    }

    // MARK: --best

    // AC9
    @Test func bestIsTheOtherAccountWithNoReachedLimitAndTheLowestSessionUse() throws {
        let f = try threeAccounts()
        let accounts = f.store.all()

        let lowestSession = BestAccount.pick(from: accounts, current: A,
                                             usage: [A: usage(0, 0), B: usage(80, 10), C: usage(20, 90)])
        let weekBreaksTie = BestAccount.pick(from: accounts, current: A,
                                             usage: [B: usage(20, 50), C: usage(20, 30)])
        let limitedExcluded = BestAccount.pick(from: accounts, current: A,
                                               usage: [B: usage(80, 10), C: usage(20, 100)])

        #expect(lowestSession?.accountId == C)
        #expect(weekBreaksTie?.accountId == C)
        #expect(limitedExcluded?.accountId == B)
    }

    // AC9
    @Test func switchBestHandsTheBestAccountToTheApp() async throws {
        let f = try threeAccounts()
        let app = AppStandIn()
        let now = Date()
        cache(f, [A: usage(90, 0), B: usage(60, 10), C: usage(5, 40)], at: now)

        let out = await AgentCommand.run(["switch", "--best"], context(f, app, now: now))

        #expect(out.code == 0)
        #expect(app.requests.map(\.request.accountId) == [C])
    }

    // AC9
    @Test func switchBestIsRefusedWhenEveryOtherAccountHasReachedALimit() async throws {
        let f = try threeAccounts()
        let app = AppStandIn()
        let now = Date()
        cache(f, [A: usage(10, 0), B: usage(100, 10), C: usage(5, 100)], at: now)

        let out = await AgentCommand.run(["switch", "--best"], context(f, app, now: now))

        #expect(out.code == 2)
        #expect(app.requests.isEmpty)
    }

    // MARK: refusals

    // AC4 / AC5
    @Test func theAppRefusesWhatThePanelWouldAskAboutUnlessForced() {
        let plain = ControlRequest(accountId: B)
        let inside = ControlRequest(accountId: B, insideDesktop: true)
        func gate(_ r: ControlRequest, busy: Bool = false, current: String? = A, working: Int = 0, saved: Bool = true) -> Refusal? {
            SwitchGate.refusal(for: r, busy: busy, current: current, working: working, isSaved: saved)
        }

        #expect(gate(plain) == nil)
        #expect(gate(plain, working: 2) == .sessionsWorking)
        #expect(gate(ControlRequest(accountId: B, force: true), working: 2) == nil)
        #expect(gate(inside) == .insideDesktop)
        #expect(gate(ControlRequest(accountId: B, force: true, insideDesktop: true), working: 2) == nil)
        #expect(gate(ControlRequest(accountId: B, force: true), busy: true) == .switching)
        #expect(gate(ControlRequest(accountId: A, force: true)) == .alreadySignedIn)
        #expect(gate(plain, saved: false) == .unknownAccount)
    }

    // AC5: the command tells the app when it runs inside Claude Desktop, and passes --force.
    @Test func switchFromInsideClaudeDesktopSaysSoAndForceIsPassedOn() async throws {
        let f = try threeAccounts()
        let app = AppStandIn()
        let desktop = ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"]

        _ = await AgentCommand.run(["switch", "bob@example.com"], context(f, app, environment: desktop))
        _ = await AgentCommand.run(["switch", "bob@example.com", "--force"], context(f, app))

        #expect(app.requests.map(\.request) == [ControlRequest(accountId: B, force: false, insideDesktop: true),
                                                 ControlRequest(accountId: B, force: true, insideDesktop: false)])
        #expect(app.requests.map(\.wait) == [true, true])
    }

    // AC3 / AC4 / AC8 / exit codes: the app's answer decides the exit code.
    @Test(arguments: [
        (Result<ControlResponse, ControlError>.success(.done(error: nil)), Int32(0)),
        (.success(.refused(.sessionsWorking)), 2),
        (.success(.done(error: "Claude opened a different account.")), 1),
        (.failure(.unreachable), 3),
        (.failure(.timedOut), 1),
    ])
    func switchExitCodeFollowsTheAppsAnswer(answer: Result<ControlResponse, ControlError>, code: Int32) async throws {
        let f = try threeAccounts()
        let app = AppStandIn()
        app.answer = answer

        let out = await AgentCommand.run(["switch", "bob@example.com", "--json"], context(f, app))

        #expect(out.code == code)
        #expect(!json(out.text).isEmpty)
    }

    @Test func noWaitReturnsOnceTheAppAccepts() async throws {
        let f = try threeAccounts()
        let app = AppStandIn()
        app.answer = .success(.accepted)

        let out = await AgentCommand.run(["switch", "bob@example.com", "--no-wait"], context(f, app))

        #expect(out.code == 0)
        #expect(app.requests.map(\.wait) == [false])
    }

    // MARK: usage

    // AC2
    @Test func usageFetchedInTheLastTwoMinutesIsReusedAndRefreshFetchesAgain() async throws {
        let f = try threeAccounts()
        let accounts = f.store.all()
        let start = Date()
        UsageStub.count = 0

        let first = await reader(f).read(accounts, current: A, refresh: false, now: start)
        let afterFirst = UsageStub.count
        _ = await reader(f).read(accounts, current: A, refresh: false, now: start.addingTimeInterval(90))
        let afterReuse = UsageStub.count
        _ = await reader(f).read(accounts, current: A, refresh: true, now: start.addingTimeInterval(100))
        let afterRefresh = UsageStub.count
        _ = await reader(f).read(accounts, current: A, refresh: false, now: start.addingTimeInterval(100 + 121))
        let afterExpiry = UsageStub.count

        #expect(afterFirst == 3)
        #expect(afterReuse == 3)
        #expect(afterRefresh == 6)
        #expect(afterExpiry == 9)
        #expect(try first[B]?.get().usage == usage(8, 34))
    }

    // AC2: the command's output says when the values were fetched.
    @Test func usageReportsEachAccountWithItsFetchTime() async throws {
        let f = try threeAccounts()
        let now = Date()
        cache(f, [A: usage(10, 20), B: usage(100, 30), C: usage(0, 0)], at: now.addingTimeInterval(-30))
        UsageStub.count = 0

        let out = await AgentCommand.run(["usage", "--json"], context(f, AppStandIn(), now: now))

        let rows = json(out.text)["accounts"] as? [[String: Any]] ?? []
        let b = rows.first { $0["accountId"] as? String == B }
        #expect(out.code == 0)
        #expect(UsageStub.count == 0)
        #expect(rows.count == 3)
        #expect((b?["session"] as? [String: Any])?["used"] as? Double == 100)
        #expect(b?["fetchedAt"] as? String != nil)
    }

    // MARK: safety

    // AC11
    @Test func noOutputContainsACredential() async throws {
        let f = try threeAccounts()
        let app = AppStandIn()
        UsageStub.count = 0
        var outputs: [String] = []
        for args in [["accounts"], ["accounts", "--json"], ["usage"], ["usage", "--json", "--refresh"],
                     ["status"], ["status", "--json"], ["switch", "bob@example.com"], ["switch", "bob@example.com", "--json"],
                     ["help"]] {
            outputs.append(await AgentCommand.run(args, context(f, app)).text)
        }

        #expect(outputs[1].contains(A))
        for text in outputs {
            #expect(!text.contains("sk-"), "\(text)")
            #expect(!text.contains("tok-"), "\(text)")
        }
    }

    // AC13: syncing stays a step of a switch.
    @Test func thereIsNoSyncCommand() async throws {
        let f = try threeAccounts()

        let out = await AgentCommand.run(["sync"], context(f, AppStandIn()))

        #expect(!AgentCommand.names.contains("sync"))
        #expect(out.code == 1)
        #expect(out.text.contains("Unknown command"))
    }

    // Bug: the app's executable run with an unknown word started a second menu bar app.
    @Test func anyWordAfterTheExecutableIsACommandAndOnlyLaunchArgumentsStartTheApp() {
        let app = "/Applications/Claude Desktop Baton.app/Contents/MacOS/ClaudeDesktopBaton"
        #expect(AgentCommand.isCommandLine([app, "sync"]))
        #expect(AgentCommand.isCommandLine([app, "accounts", "--json"]))
        #expect(AgentCommand.isCommandLine([app, "--status"]))
        #expect(AgentCommand.isCommandLine([app, "--json", "accounts"]))
        #expect(AgentCommand.isCommandLine(["/Users/me/.local/bin/claude-desktop-baton"]))
        #expect(AgentCommand.isCommandLine(["claude-desktop-baton", "help"]))
        #expect(!AgentCommand.isCommandLine([app]))
        #expect(!AgentCommand.isCommandLine([app, "-psn_0_123456"]))
        #expect(!AgentCommand.isCommandLine([app, "-NSDocumentRevisionsDebugMode", "YES"]))
    }

    @Test func helpExplainsTheRefusalsAndExitCodes() async throws {
        let f = try threeAccounts()

        let out = await AgentCommand.run(["help"], context(f, AppStandIn()))

        #expect(out.code == 0)
        for word in ["switch", "--best", "--force", "--json", "--no-wait", "--refresh", "Exit codes", "inside Claude Desktop"] {
            #expect(out.text.contains(word), "help lacks \(word)")
        }
    }
}
