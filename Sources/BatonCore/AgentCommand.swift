import Foundation

// MARK: choosing an account

/// Finds the saved account a command names: a display name, an email, or a unique account id prefix.
public enum AccountMatch: Equatable, Sendable {
    case found(SavedAccount)
    case notFound(candidates: [String])
    case ambiguous(candidates: [String])

    public static func find(_ query: String, in accounts: [SavedAccount]) -> AccountMatch {
        let names = displayNames(accounts)
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        func label(_ account: SavedAccount) -> String {
            "\(names[account.accountId] ?? account.accountId) (\(account.email ?? "no email"), \(account.accountId))"
        }
        guard !wanted.isEmpty else { return .notFound(candidates: accounts.map(label)) }
        var hits = accounts.filter { names[$0.accountId]?.lowercased() == wanted }
        if hits.isEmpty { hits = accounts.filter { $0.email?.lowercased() == wanted } }
        if hits.isEmpty, wanted.count >= 4 { hits = accounts.filter { $0.accountId.lowercased().hasPrefix(wanted) } }
        switch hits.count {
        case 1: return .found(hits[0])
        case 0: return .notFound(candidates: accounts.map(label))
        default: return .ambiguous(candidates: hits.map(label))
        }
    }
}

/// The account `switch --best` picks.
public enum BestAccount {
    /// Another account with known usage and no limit at 100%: the lowest Session percent, then the lowest Week percent.
    public static func pick(from accounts: [SavedAccount], current: String?, usage: [String: Usage]) -> SavedAccount? {
        accounts.enumerated()
            .filter { $0.element.accountId != current }
            .compactMap { index, account -> (Int, SavedAccount, Usage)? in
                guard let value = usage[account.accountId], value.session != nil || value.week != nil,
                      value.session?.isAtLimit != true, value.week?.isAtLimit != true else { return nil }
                return (index, account, value)
            }
            .min { a, b in
                (a.2.session?.used ?? 100, a.2.week?.used ?? 100, a.0) < (b.2.session?.used ?? 100, b.2.week?.used ?? 100, b.0)
            }?.1
    }
}

// MARK: switch requests

/// A switch asked for on the command line, carried out by the menu bar app.
public struct ControlRequest: Codable, Equatable, Sendable {
    public var accountId: String
    public var force: Bool
    /// The command was run by an agent inside Claude Desktop, which the switch would stop.
    public var insideDesktop: Bool
    public init(accountId: String, force: Bool = false, insideDesktop: Bool = false) {
        self.accountId = accountId; self.force = force; self.insideDesktop = insideDesktop
    }
}

public enum Refusal: String, Codable, Equatable, Sendable {
    case switching, alreadySignedIn, sessionsWorking, insideDesktop, unknownAccount

    public var message: String {
        switch self {
        case .switching: return "A switch is already in progress."
        case .alreadySignedIn: return "Claude is already signed in to that account."
        case .sessionsWorking:
            return "Sessions in Claude were active in the last 2 minutes. A switch restarts Claude, which stops them. Pass --force to switch anyway."
        case .insideDesktop:
            return "This command runs inside Claude Desktop. A switch restarts Claude, which stops this session and the others. Pass --force to switch anyway."
        case .unknownAccount: return "That account is not saved in Claude Desktop Baton."
        }
    }
}

/// What the menu bar app checks before it accepts a switch from the command line.
public enum SwitchGate {
    /// `--force` stands in for the confirmation the panel would show; it never overrides a switch in progress.
    public static func refusal(for request: ControlRequest, busy: Bool, current: String?, working: Int, isSaved: Bool) -> Refusal? {
        if busy { return .switching }
        if !isSaved { return .unknownAccount }
        if request.accountId == current { return .alreadySignedIn }
        if request.force { return nil }
        if request.insideDesktop { return .insideDesktop }
        if working > 0 { return .sessionsWorking }
        return nil
    }
}

public struct ControlResponse: Codable, Equatable, Sendable {
    public enum Event: String, Codable, Sendable { case accepted, refused, done }
    public var event: Event
    public var refusal: Refusal?
    /// For `done`: nil when Claude confirmed the target account.
    public var error: String?
    public init(event: Event, refusal: Refusal? = nil, error: String? = nil) {
        self.event = event; self.refusal = refusal; self.error = error
    }
    public static let accepted = ControlResponse(event: .accepted)
    public static func refused(_ refusal: Refusal) -> ControlResponse { ControlResponse(event: .refused, refusal: refusal) }
    public static func done(error: String?) -> ControlResponse { ControlResponse(event: .done, error: error) }
}

public enum ControlError: Error, Equatable, Sendable {
    /// No menu bar app answered, even after launching it.
    case unreachable
    case timedOut
    case broken(String)
}

// MARK: the command

/// What `status` reports that only the running system can tell.
public struct StatusFacts: Sendable {
    public var claudeRunning: Bool
    public var menuBarAppRunning: Bool
    public var workingSessions: Int
    public var legacyImportable: Int
    public var syncPreview: String
    /// Remote Control sessions running on this Mac; a switch leaves them with the account that started them.
    public var remoteSessions: [RemoteSession]
    public init(claudeRunning: Bool, menuBarAppRunning: Bool, workingSessions: Int, legacyImportable: Int, syncPreview: String,
                remoteSessions: [RemoteSession] = []) {
        self.claudeRunning = claudeRunning; self.menuBarAppRunning = menuBarAppRunning
        self.workingSessions = workingSessions; self.legacyImportable = legacyImportable; self.syncPreview = syncPreview
        self.remoteSessions = remoteSessions
    }
}

public struct AgentContext: Sendable {
    public var claude: ClaudePaths
    public var store: AccountStore
    public var usage: UsageReader
    public var environment: [String: String]
    public var now: @Sendable () -> Date
    public var status: @Sendable () -> StatusFacts
    /// The CLI's account and the saved CLI sign-ins; nil leaves them out.
    public var cli: CLIAccounts?
    /// Hands a switch to the menu bar app, launching it when needed. With `wait`, returns the final response.
    public var requestSwitch: @Sendable (ControlRequest, _ wait: Bool) async -> Result<ControlResponse, ControlError>

    public init(claude: ClaudePaths, store: AccountStore, usage: UsageReader, environment: [String: String],
                now: @escaping @Sendable () -> Date = { Date() }, status: @escaping @Sendable () -> StatusFacts,
                requestSwitch: @escaping @Sendable (ControlRequest, Bool) async -> Result<ControlResponse, ControlError>,
                cli: CLIAccounts? = nil) {
        self.claude = claude; self.store = store; self.usage = usage; self.environment = environment
        self.now = now; self.status = status; self.requestSwitch = requestSwitch; self.cli = cli
    }
}

public struct AgentOutput: Equatable, Sendable {
    public var text: String
    public var code: Int32
    public init(text: String, code: Int32) { self.text = text; self.code = code }
}

/// `claude-desktop-baton <command>`: reads run here; a switch is handed to the menu bar app.
public enum AgentCommand {
    public static let names: Set<String> = ["accounts", "status", "usage", "switch", "help"]

    public enum Exit {
        public static let success: Int32 = 0, error: Int32 = 1, refused: Int32 = 2, unreachable: Int32 = 3
    }

    public static func run(_ arguments: [String], _ context: AgentContext) async -> AgentOutput {
        var options = Options()
        var words: [String] = []
        for argument in arguments {
            switch argument {
            case "--json": options.json = true
            case "--force": options.force = true
            case "--best": options.best = true
            case "--no-wait": options.noWait = true
            case "--refresh": options.refresh = true
            case "-h", "--help": words.insert("help", at: 0)
            default:
                if argument.hasPrefix("--") { return fail("Unknown option: \(argument). Run `\(commandName) help`.", options) }
                words.append(argument)
            }
        }
        let command = words.first ?? "help"
        let rest = words.dropFirst().joined(separator: " ")
        switch command {
        case "help": return options.json ? json(["help": help], code: Exit.success) : AgentOutput(text: help, code: Exit.success)
        case "accounts": return accounts(context, options)
        case "status": return status(context, options)
        case "usage": return await usage(context, options)
        case "switch": return await switchAccount(rest, context, options)
        default: return fail("Unknown command: \(command). Run `\(commandName) help`.", options)
        }
    }

    public static let commandName = "claude-desktop-baton"

    /// Whether a process started with `arguments` is the command line rather than the menu bar app.
    /// Through the PATH link it always is; the app's own executable is the app only when started with
    /// no arguments or with the ones macOS and Xcode add at launch (`-psn_…`, `-NS…`, `-Apple…`).
    public static func isCommandLine(_ arguments: [String]) -> Bool {
        guard let executable = arguments.first else { return false }
        if URL(fileURLWithPath: executable).lastPathComponent == commandName { return true }
        guard let first = arguments.dropFirst().first else { return false }
        return !["-psn", "-NS", "-Apple"].contains { first.hasPrefix($0) }
    }

    struct Options { var json = false, force = false, best = false, noWait = false, refresh = false }

    // MARK: commands

    static func accounts(_ context: AgentContext, _ options: Options) -> AgentOutput {
        let accounts = context.store.all()
        let names = displayNames(accounts)
        let current = ClaudeLog.current(context.claude.log)?.account
        let cli = context.cli?.current().identity
        let cliSaved = context.cli?.accountsWithSavedSignIn() ?? []
        if options.json {
            return json(["accounts": accounts.map { a -> [String: Any] in
                var row: [String: Any] = ["name": names[a.accountId] ?? a.accountId, "email": a.email ?? NSNull(),
                                          "accountId": a.accountId, "orgId": a.orgId, "signedIn": a.accountId == current]
                if context.cli != nil {
                    row["cli"] = cli == a.identity
                    row["cliSignInSaved"] = cliSaved.contains(a.accountId)
                }
                return row
            }], code: Exit.success)
        }
        guard !accounts.isEmpty else { return AgentOutput(text: "No saved accounts.", code: Exit.success) }
        let lines = accounts.map { a in
            let marks = context.cli == nil ? "" : (cli == a.identity ? "  [CLI]" : "") + (cliSaved.contains(a.accountId) ? "" : "  (no CLI sign-in)")
            return "\(a.accountId == current ? "●" : " ") \(names[a.accountId] ?? a.accountId)  \(a.email ?? "-")  \(a.accountId)\(marks)"
        }
        let legend = context.cli == nil ? "● signed in to Claude Desktop"
            : "● signed in to Claude Desktop  [CLI] signed in to the Claude Code CLI; a switch moves the CLI only to accounts with a CLI sign-in"
        return AgentOutput(text: (lines + ["", legend]).joined(separator: "\n"), code: Exit.success)
    }

    static func status(_ context: AgentContext, _ options: Options) -> AgentOutput {
        let facts = context.status()
        let accounts = context.store.all()
        let names = displayNames(accounts)
        let current = ClaudeLog.current(context.claude.log)
        let signedIn = current.map { names[$0.account] ?? "unsaved account \($0.account.prefix(8))" }
        let cliState = context.cli?.current()
        let cliSaved = context.cli?.accountsWithSavedSignIn() ?? []
        let cliText: String? = cliState.map {
            switch $0 {
            case .signedOut: return "signed out"
            case .account(let id):
                if let account = accounts.first(where: { $0.identity == id }) { return names[account.accountId] ?? account.accountId }
                return "unsaved account \(id.account.prefix(8))"
            }
        }
        var cliJSON: Any = NSNull()
        if let cliState {
            var object: [String: Any] = ["signedIn": cliState != .signedOut, "accountsWithSignIn": Array(cliSaved).sorted()]
            if let id = cliState.identity { object["accountId"] = id.account; object["name"] = cliText ?? NSNull() }
            cliJSON = object
        }
        if options.json {
            return json([
                "cli": cliJSON,
                "claudeRunning": facts.claudeRunning,
                "menuBarAppRunning": facts.menuBarAppRunning,
                "signedIn": current.map { ["name": signedIn ?? "", "accountId": $0.account, "saved": names[$0.account] != nil] as [String: Any] } ?? NSNull(),
                "savedAccounts": accounts.count,
                "workingSessions": facts.workingSessions,
                "remoteControlSessions": facts.remoteSessions.map {
                    ["title": $0.title, "sessionId": $0.sessionId, "folder": $0.folder,
                     "openElsewhere": $0.openElsewhere, "resumeCommand": $0.resumeCommand] as [String: Any]
                },
                "legacyAccountsToImport": facts.legacyImportable,
                "syncPreview": facts.syncPreview,
            ], code: Exit.success)
        }
        var lines = ["Claude running: \(facts.claudeRunning)",
                     "Menu bar app running: \(facts.menuBarAppRunning)",
                     "Signed in: \(signedIn ?? "nobody")"]
        if let cliText { lines.append("CLI: \(cliText)") }
        lines.append("Saved accounts (\(accounts.count)):")
        lines += accounts.map {
            let cliMark = context.cli == nil ? "" : (cliSaved.contains($0.accountId) ? "" : "  (a switch here leaves the CLI alone: no CLI sign-in)")
            return "  \($0.accountId == current?.account ? "●" : " ") \(names[$0.accountId] ?? $0.accountId)\(cliMark)"
        }
        lines += ["Legacy accounts available to import: \(facts.legacyImportable)",
                  "Sessions working in the last 2 minutes: \(facts.workingSessions)",
                  "A switch now would sync: \(facts.syncPreview)"]
        if !facts.remoteSessions.isEmpty {
            lines.append("Remote Control sessions running (\(facts.remoteSessions.count)); a switch leaves them with the account that started them:")
            for session in facts.remoteSessions {
                lines.append("  \(session.title)\(session.openElsewhere ? "  (also open in another program)" : "")")
                lines.append("    \(session.resumeCommand)")
            }
            lines.append("  Stop a session's Remote Control server before resuming it elsewhere.")
        }
        return AgentOutput(text: lines.joined(separator: "\n"), code: Exit.success)
    }

    static func usage(_ context: AgentContext, _ options: Options) async -> AgentOutput {
        let accounts = context.store.all()
        let names = displayNames(accounts)
        let now = context.now()
        let results = await context.usage.read(accounts, current: ClaudeLog.current(context.claude.log)?.account,
                                               refresh: options.refresh, now: now)
        if options.json {
            func bucket(_ b: Usage.Bucket?) -> Any {
                guard let b else { return NSNull() }
                return ["used": b.used, "atLimit": b.isAtLimit, "resetsAt": b.resetsAt.map(iso) ?? NSNull()] as [String: Any]
            }
            return json(["accounts": accounts.map { a -> [String: Any] in
                var row: [String: Any] = ["name": names[a.accountId] ?? a.accountId, "accountId": a.accountId]
                switch results[a.accountId] {
                case .success(let snapshot)?:
                    row["session"] = bucket(snapshot.usage.session); row["week"] = bucket(snapshot.usage.week)
                    row["fetchedAt"] = iso(snapshot.fetchedAt); row["error"] = NSNull()
                case .failure(let failure)?:
                    row["session"] = NSNull(); row["week"] = NSNull(); row["fetchedAt"] = NSNull(); row["error"] = failure.reason
                case nil:
                    row["session"] = NSNull(); row["week"] = NSNull(); row["fetchedAt"] = NSNull(); row["error"] = "Not fetched."
                }
                return row
            }], code: Exit.success)
        }
        guard !accounts.isEmpty else { return AgentOutput(text: "No saved accounts.", code: Exit.success) }
        func text(_ label: String, _ b: Usage.Bucket?) -> String {
            guard let b else { return "\(label) —" }
            let reset = b.isAtLimit ? b.resetsAt.map { " (resets in \(UsageText.until($0, from: now)))" } ?? "" : ""
            return "\(label) \(UsageText.percent(b.used))\(reset)"
        }
        let lines = accounts.map { a -> String in
            let name = names[a.accountId] ?? a.accountId
            switch results[a.accountId] {
            case .success(let s)?:
                return "\(name): \(text("Session", s.usage.session)) · \(text("Week", s.usage.week)) · fetched \(s.fetchedAt.formatted(date: .omitted, time: .standard))"
            case .failure(let failure)?: return "\(name): — \(failure.reason)"
            case nil: return "\(name): —"
            }
        }
        return AgentOutput(text: lines.joined(separator: "\n"), code: Exit.success)
    }

    static func switchAccount(_ query: String, _ context: AgentContext, _ options: Options) async -> AgentOutput {
        let accounts = context.store.all()
        let names = displayNames(accounts)
        let target: SavedAccount
        if options.best {
            guard query.isEmpty else { return fail("Pass an account or --best, not both.", options) }
            let current = ClaudeLog.current(context.claude.log)?.account
            let results = await context.usage.read(accounts, current: current, refresh: false, now: context.now())
            let known = results.compactMapValues { try? $0.get().usage }
            guard let best = BestAccount.pick(from: accounts, current: current, usage: known) else {
                return refused("No other account has room: each has reached a limit or its usage could not be fetched.",
                               refusal: nil, options)
            }
            target = best
        } else {
            guard !query.isEmpty else { return fail("Name an account, or pass --best. Run `\(commandName) accounts` to list them.", options) }
            switch AccountMatch.find(query, in: accounts) {
            case .found(let account): target = account
            case .notFound(let candidates):
                return fail("No saved account matches \"\(query)\".", options, candidates: candidates)
            case .ambiguous(let candidates):
                return fail("More than one saved account matches \"\(query)\".", options, candidates: candidates)
            }
        }

        let name = names[target.accountId] ?? target.accountId
        let account: [String: Any] = ["name": name, "accountId": target.accountId]
        let request = ControlRequest(accountId: target.accountId, force: options.force,
                                     insideDesktop: context.environment["CLAUDE_CODE_ENTRYPOINT"] == "claude-desktop")
        func out(_ result: String, _ message: String, _ code: Int32, _ extra: [String: Any] = [:]) -> AgentOutput {
            options.json ? json(["result": result, "account": account, "message": message].merging(extra) { $1 }, code: code)
                         : AgentOutput(text: message, code: code)
        }
        switch await context.requestSwitch(request, !options.noWait) {
        case .success(let response):
            switch response.event {
            case .accepted:
                return out("accepted", "The switch to \(name) has started in the menu bar app.", Exit.success)
            case .refused:
                let refusal = response.refusal ?? .switching
                return out("refused", refusal.message, Exit.refused, ["refusal": refusal.rawValue])
            case .done:
                if let error = response.error {
                    return out("failed", "Couldn't switch to \(name): \(error)", Exit.error, ["error": error])
                }
                return out("switched", "Switched to \(name).", Exit.success)
            }
        case .failure(.unreachable):
            return out("unreachable", "The Claude Desktop Baton menu bar app could not be reached or launched.", Exit.unreachable)
        case .failure(.timedOut):
            return out("timedOut", "The menu bar app has not finished the switch; it may still be running. Check with `\(commandName) status`.", Exit.error)
        case .failure(.broken(let message)):
            return out("failed", message, Exit.error)
        }
    }

    // MARK: output

    static func fail(_ message: String, _ options: Options, candidates: [String] = []) -> AgentOutput {
        if options.json {
            var body: [String: Any] = ["error": message]
            if !candidates.isEmpty { body["candidates"] = candidates }
            return json(body, code: Exit.error)
        }
        let list = candidates.isEmpty ? "" : "\nSaved accounts:\n" + candidates.map { "  \($0)" }.joined(separator: "\n")
        return AgentOutput(text: message + list, code: Exit.error)
    }

    static func refused(_ message: String, refusal: Refusal?, _ options: Options) -> AgentOutput {
        options.json ? json(["result": "refused", "message": message, "refusal": refusal?.rawValue ?? NSNull()], code: Exit.refused)
                     : AgentOutput(text: message, code: Exit.refused)
    }

    static func json(_ object: [String: Any], code: Int32) -> AgentOutput {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return AgentOutput(text: String(decoding: data, as: UTF8.self), code: code)
    }

    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    static let help = """
    \(commandName): see and switch the Claude accounts saved in Claude Desktop Baton.

    Commands:
      accounts             Saved accounts in panel order; the one Claude Desktop is signed in to is marked.
      status               Claude and the menu bar app running?, signed-in account, working sessions, what a switch would sync,
                           and the Remote Control sessions a switch leaves behind, each with its resume command.
      usage [--refresh]    Session (5-hour) and Week percent used per account. Values fetched in the last
                           2 minutes are reused; --refresh fetches again.
      switch <account>     Switch Claude Desktop to an account: its name, email, or the start of its account id.
      switch --best        Switch to the other account with no limit at 100% and the lowest Session use.
      help                 This text.

    Options:
      --json               Machine-readable output for any command.
      --force              Switch even when Claude sessions were active in the last 2 minutes, or when this
                           command runs inside Claude Desktop.
      --no-wait            Return once the menu bar app accepts the switch instead of waiting for the outcome.

    How a switch works:
      The menu bar app performs it, launching first if needed: Claude quits, Code sessions are synced,
      the account's sign-in is put in place, and Claude reopens. It takes up to about a minute and a half,
      and finishes even if this command is stopped. The user sees the menu bar spinner and any failure alert.
      A switch is refused (exit code 2) when a switch is already running, the account is already signed in,
      Claude sessions were active in the last 2 minutes, or the command runs inside Claude Desktop, where the
      restart would stop this very session and the others. --force overrides the last two.

    Exit codes:
      0  success          1  error or failed switch
      2  refused          3  the menu bar app could not be reached or launched

    Adding and removing accounts is done in the menu bar panel. No output contains credentials.
    """
}

// MARK: usage for the command

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var usage: Usage
    public var fetchedAt: Date
    public init(usage: Usage, fetchedAt: Date) { self.usage = usage; self.fetchedAt = fetchedAt }
}

/// Usage last fetched for each account, shared by the menu bar app and the command. Holds no credentials.
public final class UsageCache: @unchecked Sendable {
    public let file: URL
    private let lock = NSLock()
    public init(file: URL) { self.file = file }

    public func load() -> [String: UsageSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    public func store(_ accountId: String, _ snapshot: UsageSnapshot) {
        lock.lock(); defer { lock.unlock() }
        var all = read()
        all[accountId] = snapshot
        if let data = try? JSONEncoder().encode(all) { try? writePrivate(data, to: file) }
    }

    private func read() -> [String: UsageSnapshot] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: UsageSnapshot].self, from: data)) ?? [:]
    }
}

/// Usage for the command: values fetched in the last 2 minutes are reused.
public struct UsageReader: Sendable {
    public let cache: UsageCache
    public let client: UsageClient
    public let claude: ClaudePaths
    public init(cache: UsageCache, client: UsageClient, claude: ClaudePaths) {
        self.cache = cache; self.client = client; self.claude = claude
    }

    /// The signed-in account uses Claude's live cookies, the others their saved copies, as in the panel.
    public func read(_ accounts: [SavedAccount], current: String?, refresh: Bool, now: Date) async -> [String: Result<UsageSnapshot, UsageFailure>] {
        let cached = cache.load()
        var results: [String: Result<UsageSnapshot, UsageFailure>] = [:]
        var due: [SavedAccount] = []
        for account in accounts {
            if !refresh, let snapshot = cached[account.accountId],
               (0..<UsageSchedule.interval).contains(now.timeIntervalSince(snapshot.fetchedAt)) {
                results[account.accountId] = .success(snapshot)
            } else {
                due.append(account)
            }
        }
        let live = due.contains { $0.accountId == current } ? try? SignInStore.read(claude) : nil
        let fetched = await withTaskGroup(of: (String, Result<Usage, UsageFailure>).self) { group in
            for account in due {
                let signIn = account.accountId == current ? (live ?? account.signIn) : account.signIn
                group.addTask { (account.accountId, await client.usage(orgId: account.orgId, signIn: signIn)) }
            }
            var all: [(String, Result<Usage, UsageFailure>)] = []
            for await item in group { all.append(item) }
            return all
        }
        for (id, result) in fetched {
            switch result {
            case .success(let usage):
                let snapshot = UsageSnapshot(usage: usage, fetchedAt: now)
                cache.store(id, snapshot)
                results[id] = .success(snapshot)
            case .failure(let failure):
                results[id] = .failure(failure)
            }
        }
        return results
    }
}
