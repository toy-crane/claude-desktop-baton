import Foundation
import Testing
@testable import BatonCore

/// Remote Control sessions have no record a switch could copy, so the app only finds them
/// and hands out their resume commands. Registry entries are shaped like Claude Code 2.1.319's.
@Suite("Remote Control sessions")
struct RemoteSessionsTests {
    let registry: URL
    let worktree = "/Users/someone/code/dearly/.claude/worktrees/bridge-cse_018VgFUsYyoZ3YBr36qPc7vF"

    init() throws {
        registry = FileManager.default.temporaryDirectory.appendingPathComponent("baton-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
    }

    private func register(pid: Int, session: String, cwd: String, entrypoint: String = "sdk-cli",
                          bridge: String? = "session_018VgFUsYyoZ3YBr36qPc7vF", name: String? = nil,
                          nameSource: String = "derived") throws {
        var body: [String: Any] = ["pid": pid, "sessionId": session, "cwd": cwd, "entrypoint": entrypoint,
                                   "kind": "interactive", "nameSource": nameSource, "status": "idle"]
        body["bridgeSessionId"] = bridge
        body["name"] = name
        try JSONSerialization.data(withJSONObject: body).write(to: registry.appendingPathComponent("\(pid).json"))
    }

    private func running(alive: Set<Int32> = [1, 2, 3, 4, 5]) -> [RemoteSession] {
        RemoteSessions.running(registry: registry, isAlive: { alive.contains($0) })
    }

    @Test func findsTheSessionsARemoteControlServerIsRunning() throws {
        try register(pid: 1, session: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", cwd: worktree,
                     name: "Plan the memory layout", nameSource: "auto")
        // Claude Desktop's own sessions and plain terminal sessions are not Remote Control sessions.
        try register(pid: 2, session: "e08d65b8-2145-46a4-ab83-606c1442c22b", cwd: "/Users/someone/code/dearly",
                     entrypoint: "claude-desktop", name: "Disk check", nameSource: "user")
        try register(pid: 3, session: "0f0f0f0f-2145-46a4-ab83-606c1442c22b", cwd: "/Users/someone/code/dearly",
                     entrypoint: "cli", bridge: nil)
        // An SDK session without a bridge id was not started by a Remote Control server.
        try register(pid: 4, session: "1a1a1a1a-2145-46a4-ab83-606c1442c22b", cwd: "/Users/someone/code/dearly", bridge: nil)

        let sessions = running()

        #expect(sessions == [RemoteSession(sessionId: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", folder: worktree,
                                           name: "Plan the memory layout")])
        #expect(sessions.first?.title == "dearly · Plan the memory layout")
    }

    @Test func aSessionWhoseProcessHasExitedIsNotListed() throws {
        try register(pid: 1, session: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", cwd: worktree)

        #expect(running(alive: []).isEmpty)
        #expect(running(alive: [1]).count == 1)
    }

    // A name derived from the folder ("bridge-cse-018vg…-62") says nothing; the id's start stands in.
    @Test func aSessionWithoutATitleIsShownByItsProjectAndId() throws {
        try register(pid: 1, session: "5a1a77f5-8215-5a78-8cc7-db3f78c0e914", cwd: worktree,
                     name: "bridge-cse-018vgfusyyoz3ybr36qpc7vf-51")

        let session = try #require(running().first)

        #expect(session.name == nil)
        #expect(session.title == "dearly · 5a1a77f5")
    }

    // Found on this Mac: a session resumed in a terminal while its server still ran it had two writers.
    @Test func aSessionAlsoOpenInAnotherProgramIsMarked() throws {
        try register(pid: 1, session: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", cwd: worktree)
        try register(pid: 2, session: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", cwd: worktree, entrypoint: "cli", bridge: nil)

        #expect(running().map(\.openElsewhere) == [true])
        #expect(running(alive: [1]).map(\.openElsewhere) == [false])
    }

    @Test func theResumeCommandOpensTheSessionInItsOwnFolder() {
        let session = RemoteSession(sessionId: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", folder: worktree)
        let quoted = RemoteSession(sessionId: "abc", folder: "/Users/someone/it's here/repo")

        #expect(session.resumeCommand == "cd '\(worktree)' && claude --resume b2da6403-1087-5f10-929c-77c6fe7a8aaf")
        #expect(quoted.resumeCommand == #"cd '/Users/someone/it'\''s here/repo' && claude --resume abc"#)
        #expect(quoted.project == "repo")
        #expect(RemoteSessions.resumeCommands([session, quoted]).split(separator: "\n").count == 2)
    }

    // The id goes into a shell command: an entry whose id is not id-shaped is left out.
    @Test func entriesThatAreNotWhatClaudeCodeWritesAreIgnored() throws {
        try register(pid: 1, session: "x; rm -rf ~", cwd: worktree)
        try Data("not json".utf8).write(to: registry.appendingPathComponent("2.json"))
        try Data("{}".utf8).write(to: registry.appendingPathComponent("3.json"))
        try Data("{}".utf8).write(to: registry.appendingPathComponent("4.abc.key"))

        #expect(running().isEmpty)
        #expect(RemoteSessions.running(registry: registry.appendingPathComponent("missing")).isEmpty)
    }

    @Test func sessionsAreListedByProjectThenTitle() throws {
        try register(pid: 1, session: "33333333-0000-4000-8000-000000000003", cwd: "/Users/someone/code/playbook/.claude/worktrees/bridge-cse_b")
        try register(pid: 2, session: "22222222-0000-4000-8000-000000000002", cwd: worktree, name: "B", nameSource: "auto")
        try register(pid: 3, session: "11111111-0000-4000-8000-000000000001", cwd: worktree, name: "A", nameSource: "user")

        #expect(running().map(\.title) == ["dearly · A", "dearly · B", "playbook · 33333333"])
    }

    // MARK: what the switch says about them

    @Test func selectingAnotherAccountAsksFirstWhenRemoteControlSessionsAreRunning() {
        let current = Identity(account: ClaudeFixture.a, org: ClaudeFixture.org)

        #expect(SwitchDecision.onSelect(ClaudeFixture.b, current: current, working: 0, remote: 2) == .confirm(working: 0, remote: 2))
        #expect(SwitchDecision.onSelect(ClaudeFixture.b, current: current, working: 1, remote: 2) == .confirm(working: 1, remote: 2))
        #expect(SwitchDecision.onSelect(ClaudeFixture.a, current: current, working: 0, remote: 2) == .none)
        #expect(SwitchDecision.onSelect(ClaudeFixture.b, current: current, working: 0, remote: 0) == .start)
    }

    @Test func theConfirmationSaysRemoteControlSessionsStayBehindAndOffersTheirResumeCommands() {
        let alert = Alerts.confirmSwitch(to: "Acme · sam", working: 0, remote: 2)
        let both = Alerts.confirmSwitch(to: "Acme · sam", working: 1, remote: 1)

        #expect(alert.message.hasPrefix("2 Remote Control sessions are running on this Mac."))
        #expect(alert.message.contains("stay listed under the account that started them, not under Acme · sam"))
        #expect(alert.message.contains("stop its Remote Control server first"))
        #expect(alert.buttons == ["Switch", "Cancel", "Copy Commands and Switch"])
        #expect(both.message.hasPrefix("1 session is working in Claude."))
        #expect(both.message.contains("\n\n1 Remote Control session is running on this Mac."))
    }

    @Test func thePanelCountsRemoteControlSessions() {
        func state(_ remote: [RemoteSession]) -> PanelState {
            PanelState.make(accounts: [], current: nil, usage: [:], phase: .idle, now: Date(), remote: remote)
        }
        let one = RemoteSession(sessionId: "a", folder: worktree), two = RemoteSession(sessionId: "b", folder: worktree)

        #expect(state([]).remoteNote == nil)
        #expect(state([one]).remoteNote == "1 Remote Control session")
        #expect(state([one, two]).remoteNote == "2 Remote Control sessions")
        #expect(state([one, two]).remote == [one, two])
    }

    @Test func statusListsRemoteControlSessionsWithTheirResumeCommands() async throws {
        let f = try ClaudeFixture(signedIn: ClaudeFixture.a)
        let session = RemoteSession(sessionId: "b2da6403-1087-5f10-929c-77c6fe7a8aaf", folder: worktree,
                                    name: "Plan the memory layout", openElsewhere: true)
        let usage = UsageReader(cache: UsageCache(file: f.app.usageCache),
                                client: UsageClient(protocolClasses: [], userAgent: "test", key: { Data(count: 16) }),
                                claude: f.claude)
        let context = AgentContext(claude: f.claude, store: f.store, usage: usage, environment: [:], now: { Date() },
                                   status: { StatusFacts(claudeRunning: true, menuBarAppRunning: false, workingSessions: 0,
                                                         legacyImportable: 0, syncPreview: "nothing to change",
                                                         remoteSessions: [session]) },
                                   requestSwitch: { _, _ in .failure(.unreachable) })

        let text = await AgentCommand.run(["status"], context)
        let json = await AgentCommand.run(["status", "--json"], context)

        #expect(text.text.contains("Remote Control sessions running (1)"))
        #expect(text.text.contains("dearly · Plan the memory layout  (also open in another program)"))
        #expect(text.text.contains(session.resumeCommand))
        let body = try #require(try JSONSerialization.jsonObject(with: Data(json.text.utf8)) as? [String: Any])
        let rows = try #require(body["remoteControlSessions"] as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["resumeCommand"] as? String == session.resumeCommand)
        #expect(rows[0]["openElsewhere"] as? Bool == true)
        #expect(rows[0]["title"] as? String == "dearly · Plan the memory layout")
    }
}
