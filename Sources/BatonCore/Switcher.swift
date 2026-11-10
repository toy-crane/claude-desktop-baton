import Foundation

/// The running Claude Desktop app, as the switch needs it. Replaced by a fake in tests.
public protocol ClaudeApp: AnyObject {
    var isRunning: Bool { get }
    /// Asks Claude to quit normally.
    func quit()
    func open() async throws
    /// Opens a `claude://` link in Claude, as Claude Code's `/desktop` command does.
    func open(link: URL) async throws
}

public struct SwitchTiming: Sendable {
    public var quitTimeout: Duration = .seconds(45)
    public var loadTimeout: Duration = .seconds(45)
    public var poll: Duration = .milliseconds(250)
    /// Between two links handed to Claude, so each session is taken over before the next arrives.
    public var linkGap: Duration = .seconds(2)
    public init() {}
}

public enum SwitchStep: Sendable, Equatable {
    case quitting, syncing, signingIn, opening, confirming
}

public struct SwitchResult: Sendable {
    /// nil when Claude confirmed the target account.
    public var error: BatonError?
    public var sync: SyncReport?
    /// The account that was signed in before; offered as "Put back" after a failure.
    public var previous: Identity?
    /// Whether Claude's sign-in was replaced; without that there is nothing to put back.
    public var signInChanged = false
    /// What happened to the Claude Code CLI; nil when the switch did not reach it.
    public var cli: CLIFollow?
    /// Remote Control sessions handed to Claude Desktop after the switch, so they are listed under the target.
    public var remoteOpened: [RemoteSession] = []
}

public final class Switcher: @unchecked Sendable {
    public let claude: ClaudePaths
    public let paths: AppPaths
    public let store: AccountStore
    let app: ClaudeApp
    let timing: SwitchTiming
    /// Moves the Claude Code CLI after Claude confirms the target; nil leaves the CLI alone.
    public let cli: CLIAccounts?

    public init(claude: ClaudePaths, paths: AppPaths, store: AccountStore, app: ClaudeApp, timing: SwitchTiming = SwitchTiming(),
                cli: CLIAccounts? = nil) {
        self.claude = claude
        self.paths = paths
        self.store = store
        self.app = app
        self.timing = timing
        self.cli = cli
    }

    /// Quit Claude, re-save the outgoing sign-in, sync sessions, put the target's sign-in
    /// in place, reopen Claude, wait for it to confirm the target account, then hand it the
    /// running Remote Control sessions it has no record of.
    public func switchTo(_ target: SavedAccount, progress: @Sendable (SwitchStep) -> Void = { _ in }) async -> SwitchResult {
        let outgoing = ClaudeLog.current(claude.log)
        if outgoing?.account == target.accountId && app.isRunning { return SwitchResult(previous: outgoing) }
        var result = await restart(into: target.signIn, expecting: target.accountId, outgoing: outgoing, progress: progress)
        // The CLI follows only once Claude has confirmed the target, so a failed switch never splits them.
        if result.error == nil, let cli { result.cli = cli.follow(target) }
        if result.error == nil { result.remoteOpened = await handOverRemoteSessions() }
        return result
    }

    /// Remote Control sessions are listed by the account that started their server and have no record
    /// to sync. Once Claude is open on the target, each one without a record is opened with the link
    /// `/desktop` uses; Claude writes the record itself, and every later switch syncs it like any other.
    private func handOverRemoteSessions() async -> [RemoteSession] {
        let waiting = RemoteSessions.notInClaudeDesktop(RemoteSessions.running(registry: claude.cliSessions),
                                                        sessionsRoot: claude.sessionsRoot)
        var opened: [RemoteSession] = []
        for session in waiting {
            guard let link = session.desktopLink else { continue }
            if !opened.isEmpty { try? await Task.sleep(for: timing.linkGap) }
            if (try? await app.open(link: link)) != nil { opened.append(session) }
        }
        return opened
    }

    /// Like a switch, but Claude reopens signed out on this Mac only, so another account can sign in.
    /// The outgoing account's server-side session is not ended.
    public func addAccount(progress: @Sendable (SwitchStep) -> Void = { _ in }) async -> SwitchResult {
        let outgoing = ClaudeLog.current(claude.log)
        let empty: SignIn
        do { empty = try SignInStore.read(claude).signedOut() } catch {
            return SwitchResult(error: error as? BatonError ?? BatonError(error.localizedDescription), previous: outgoing)
        }
        return await restart(into: empty, expecting: nil, outgoing: outgoing, progress: progress)
    }

    private func restart(into signIn: SignIn, expecting target: String?, outgoing: Identity?,
                         progress: @Sendable (SwitchStep) -> Void) async -> SwitchResult {
        var result = SwitchResult(previous: outgoing)
        progress(.quitting)
        guard await quitClaude() else {
            result.error = BatonError("Claude stayed open, so nothing was changed. Close any dialog Claude is showing, then try again.")
            return result
        }

        // Keep a token Claude refreshed since the last save, but only when the log and the
        // stored sign-in agree on who is signed in.
        let current: SignIn
        do { current = try SignInStore.read(claude) } catch {
            try? await app.open()
            result.error = error as? BatonError ?? BatonError(error.localizedDescription)
            return result
        }
        if let outgoing, outgoing.account != target, current.hasTokens, current.hasSessionKey,
           current.accountId == outgoing.account {
            let existing = store.load(outgoing.account)
            try? store.save(SavedAccount(accountId: outgoing.account, orgId: outgoing.org,
                                         email: existing?.email, orgName: existing?.orgName,
                                         savedAt: Date().timeIntervalSince1970 * 1000, signIn: current))
        }

        progress(.syncing)
        result.sync = SessionSync.run(paths.syncLocations(claude))

        progress(.signingIn)
        do {
            try writePrivate(JSONEncoder().encode(current), to: paths.previousSignIn)
            try SignInStore.replace(with: signIn, claude)
            result.signInChanged = true
        } catch {
            try? await app.open()
            result.error = error as? BatonError ?? BatonError(error.localizedDescription)
            return result
        }

        let offset = ClaudeLog.size(claude.log)
        progress(.opening)
        do { try await app.open() } catch {
            result.error = BatonError("The sign-in is in place, but Claude did not reopen. Open it from Applications.")
            return result
        }
        guard let target else { return result }

        progress(.confirming)
        let deadline = ContinuousClock.now + timing.loadTimeout
        while ContinuousClock.now < deadline {
            if let loaded = ClaudeLog.identity(in: claude.log, after: offset) {
                if loaded.account != target {
                    result.error = BatonError("Claude opened a different account. The saved sign-in may have expired; sign in to it in Claude and it is saved again.")
                }
                return result
            }
            try? await Task.sleep(for: timing.poll)
        }
        result.error = BatonError("Claude has not confirmed the account. If it shows a sign-in screen, the saved sign-in has expired.")
        return result
    }

    private func quitClaude() async -> Bool {
        guard app.isRunning else { return true }
        app.quit()
        let deadline = ContinuousClock.now + timing.quitTimeout
        while app.isRunning {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: timing.poll)
        }
        return true
    }

    /// The signed-in account, when Claude's log and its stored sign-in agree on who that is.
    public func captureCurrent(now: Date = Date()) throws -> SavedAccount {
        guard let identity = ClaudeLog.current(claude.log) else { throw BatonError("Claude is not signed in.") }
        let signIn = try SignInStore.read(claude)
        guard signIn.hasTokens, signIn.hasSessionKey else { throw BatonError("Claude is not fully signed in.") }
        guard signIn.accountId == identity.account else { throw BatonError("Claude is still switching accounts.") }
        return SavedAccount(accountId: identity.account, orgId: identity.org, savedAt: now.timeIntervalSince1970 * 1000, signIn: signIn)
    }

    /// Saves the signed-in account when it is not saved yet. Returns it when it was saved.
    @discardableResult
    public func saveCurrentIfNew(now: Date = Date()) -> SavedAccount? {
        guard let current = try? captureCurrent(now: now), store.load(current.accountId) == nil,
              (try? store.save(current)) != nil else { return nil }
        return store.load(current.accountId)
    }

    /// Sessions in the signed-in account's folder with activity in the last `window`:
    /// a switch would stop their work. Claude updates a record's `lastActivityAt` only when a
    /// turn starts, so a session whose conversation file is still being written counts too.
    public func workingSessions(now: Date = Date(), window: TimeInterval = 120) -> Int {
        guard let identity = ClaudeLog.current(claude.log) else { return 0 }
        let fm = FileManager.default
        let folder = claude.sessionFolder(identity)
        let cutoff = now.addingTimeInterval(-window)

        // Conversations written in the window, by Claude Code session id: a cheap listing.
        var recent: Set<String> = []
        for project in (try? fm.contentsOfDirectory(atPath: claude.projects.path)) ?? [] {
            let dir = claude.projects.appendingPathComponent(project)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".jsonl") {
                if let modified = (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.modificationDate] as? Date,
                   modified >= cutoff { recent.insert(String(name.dropLast(6))) }
            }
        }

        // Archived sessions cannot be working; Claude's own hint lists them, so most records are never read.
        let archived = Set(SessionSync.readHint(folder.appendingPathComponent(SessionSync.hintFile)) ?? [])
        var working = 0
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            guard let id = SessionSync.match(SessionSync.recordName, name), !archived.contains(id) else { continue }
            let url = folder.appendingPathComponent(name)
            guard case .success(let entry)? = SessionSync.entry(url, id: id) else { continue }
            // Without a recent conversation, only a record rewritten in the window can be working.
            guard !recent.isEmpty || entry.modified >= cutoff, let body = SessionSync.fields(url, id: id),
                  body["isArchived"] as? Bool != true else { continue }
            if let activity = (body["lastActivityAt"] as? NSNumber)?.doubleValue,
               Date(timeIntervalSince1970: activity / 1000) >= cutoff { working += 1; continue }
            if let cli = body["cliSessionId"] as? String, recent.contains(cli) { working += 1 }
        }
        return working
    }
}
