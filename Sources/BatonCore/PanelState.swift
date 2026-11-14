import Foundation

/// What the menu bar panel shows, derived from saved accounts, usage, and the switch in progress.
/// Kept free of UI code so the rules can be tested. Switching messages are alerts, not panel content.
public struct UsageEntry: Equatable, Sendable {
    public var usage: Usage?
    public var failure: UsageFailure?
    public var lastAttempt: Date?
    public var checked: Date?
    public init(usage: Usage? = nil, failure: UsageFailure? = nil, lastAttempt: Date? = nil, checked: Date? = nil) {
        self.usage = usage; self.failure = failure; self.lastAttempt = lastAttempt; self.checked = checked
    }
}

public enum Phase: Equatable, Sendable {
    case idle
    case switching(accountId: String)
    case adding
}

public struct Meter: Equatable, Sendable {
    public let fraction: Double
    public let text: String
    public let atLimit: Bool
    /// When this limit resets, as `UsageText.resetLabel` writes it; nil when unknown or already past.
    public var reset: String?
    public init(fraction: Double, text: String, atLimit: Bool, reset: String? = nil) {
        self.fraction = fraction; self.text = text; self.atLimit = atLimit; self.reset = reset
    }
}

/// The meter of one model weekly limit, labeled with the model's name.
public struct ModelMeter: Equatable, Sendable {
    public let name: String
    public let meter: Meter
}

public struct AccountRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isCurrent: Bool
    public let isTarget: Bool
    public let isDisabled: Bool
    public let session: Meter
    public let week: Meter
    /// One meter per model weekly limit, shown under Week; empty for most accounts.
    public var models: [ModelMeter] = []
    /// Why usage is unavailable, shown on hover beside the name.
    public let failureReason: String?
    public let tooltip: String
    public let email: String?
    /// The Claude Code CLI is signed in to this account.
    public var isCLI = false
    /// The last fetched Week limit is at 100% and has not reset yet. Session and model limits do not count.
    public var isOutOfWeek = false
    public var limitResets: [Usage.LimitReset] = []
    public var limitResetCount: UInt64 { limitResets.reduce(0) { $0 + UInt64($1.remaining) } }
}

public enum SwitchDecision: Equatable, Sendable {
    case none, confirm(working: Int), start

    /// Clicking an account: the current one does nothing; another asks first when sessions are working.
    public static func onSelect(_ accountId: String, current: Identity?, working: Int) -> SwitchDecision {
        if accountId == current?.account { return .none }
        return working > 0 ? .confirm(working: working) : .start
    }
}

/// The text of an alert: the first button is the default.
public struct AlertContent: Equatable, Sendable {
    public let title: String
    public let message: String
    public let buttons: [String]
    public init(title: String, message: String, buttons: [String]) {
        self.title = title; self.message = message; self.buttons = buttons
    }
}

public enum Alerts {
    public static func confirmSwitch(to name: String, working: Int) -> AlertContent {
        let sessions = working == 1 ? "1 session is" : "\(working) sessions are"
        return AlertContent(title: "Switch to \(name)?",
                            message: "\(sessions) working in Claude. Switching restarts Claude, which stops them; you can resume them afterwards.",
                            buttons: ["Switch", "Cancel"])
    }

    public static func switchFailed(to name: String, message: String, putBack: String?) -> AlertContent {
        AlertContent(title: "Couldn't switch to \(name)", message: message,
                     buttons: putBack.map { ["Put Back \($0)", "OK"] } ?? ["OK"])
    }

    public static func syncSkipped(to name: String, reason: String) -> AlertContent {
        AlertContent(title: "Switched to \(name)",
                     message: "Sessions were not synced: \(reason). They are brought in line at the next switch.",
                     buttons: ["OK"])
    }

    public static let addAccountReady = AlertContent(
        title: "Sign in to another account",
        message: "Claude reopened signed out on this Mac. Sign in to another account in Claude; it is saved automatically. To have the CLI follow it too, run `claude` and `/login` as that account once.",
        buttons: ["OK"])

    public static func commandLineInstalled(onPath: Bool?) -> AlertContent {
        let message: String
        switch onPath {
        case true?:
            message = "Agents and scripts can now run `claude-desktop-baton help` in a new terminal."
        case false?:
            message = "~/.local/bin is not on your PATH, so terminals will not find it yet. Add this line to your shell profile (for example ~/.zshrc), then open a new terminal:\n\nexport PATH=\"$HOME/.local/bin:$PATH\""
        case nil:
            message = "It is in ~/.local/bin. If a new terminal cannot find `claude-desktop-baton`, add this line to your shell profile:\n\nexport PATH=\"$HOME/.local/bin:$PATH\""
        }
        return AlertContent(title: "Command line tool installed", message: message, buttons: ["OK"])
    }

    public static func commandLineFailed(_ message: String) -> AlertContent {
        AlertContent(title: "Couldn't install the command line tool", message: message, buttons: ["OK"])
    }

    /// After a switch whose target has no saved CLI sign-in. `cli` names the CLI's account, nil when signed out.
    public static func cliNotFollowing(to name: String, cli: String?) -> AlertContent {
        let state = cli.map { "The CLI is still on \($0)." } ?? "The CLI is signed out."
        return AlertContent(title: "Switched to \(name)",
                            message: "\(state) Run `claude` and `/login` as \(name) once; after that it follows every switch.",
                            buttons: ["OK"])
    }

    public static func cliFailed(to name: String, previous: String?, message: String) -> AlertContent {
        AlertContent(title: "Switched to \(name)",
                     message: "The CLI stayed on \(previous ?? "its previous account"): \(message)", buttons: ["OK"])
    }

    public static func confirmRemove(_ name: String) -> AlertContent {
        AlertContent(title: "Remove \(name)?",
                     message: "Only its saved sign-in is deleted from Claude Desktop Baton. Claude and your sessions are not changed.",
                     buttons: ["Remove", "Cancel"])
    }
}

public struct PanelState: Equatable, Sendable {
    public let rows: [AccountRow]
    /// The signed-in account, shown apart at the top; nil when it is not saved.
    public var signedIn: AccountRow? { rows.first(where: \.isCurrent) }
    /// Every other saved account that still has Week left, by name.
    public var switchTo: [AccountRow] { rows.filter { !$0.isCurrent && !$0.isOutOfWeek } }
    /// Every other saved account whose Week limit is used up, by name; shown in a group at the bottom.
    public var weekLimitReached: [AccountRow] { rows.filter { !$0.isCurrent && $0.isOutOfWeek } }
    public let busy: Bool
    /// "updated 1 min ago", for the "⋯" menu.
    public let updated: String?
    /// For the "⋯" menu when no saved account carries the CLI tag: "CLI: signed out", "CLI: not on a saved account".
    public var cliNote: String?

    public static func make(accounts: [SavedAccount], current: Identity?, usage: [String: UsageEntry],
                            phase: Phase, now: Date, cli: CLIState? = nil, cliSaved: Set<String> = []) -> PanelState {
        let names = displayNames(accounts)
        var target: String?
        let busy: Bool
        switch phase {
        case .idle: busy = false
        case .switching(let id): busy = true; target = id
        case .adding: busy = true
        }

        func meter(_ bucket: Usage.Bucket?, weekly: Bool = false) -> Meter {
            guard let bucket else { return Meter(fraction: 0, text: "—", atLimit: false) }
            return Meter(fraction: bucket.used / 100, text: UsageText.percent(bucket.used), atLimit: bucket.isAtLimit,
                         reset: bucket.resetsAt.flatMap { date -> String? in
                             guard date > now else { return nil }
                             // The Session limit is at most five hours away; only the Week one can be days away.
                             return weekly ? UsageText.resetLabel(date, from: now) : UsageText.until(date, from: now)
                         })
        }
        func when(_ date: Date?) -> String {
            guard let date else { return "unknown" }
            return date.formatted(date: Calendar.current.isDate(date, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened)
        }

        let rows = accounts.map { account -> AccountRow in
            let entry = usage[account.accountId]
            let shown = entry?.failure == nil ? entry?.usage : nil
            var tooltip = [account.email ?? account.accountId]
            if cli != nil, !cliSaved.contains(account.accountId) { tooltip.append("CLI not signed in yet") }
            if let shown {
                tooltip.append("Session resets \(when(shown.session?.resetsAt)) · Week resets \(when(shown.week?.resetsAt))")
                for limit in shown.models {
                    var line = "\(limit.name) resets \(when(limit.bucket.resetsAt))"
                    if let allowance = limit.allowancePercent { line += " · up to \(Int(allowance.rounded()))% of Week" }
                    tooltip.append(line)
                }
            }
            // A failed refresh keeps the model meters the account had, reading "—".
            let models = (entry?.usage?.models ?? []).map {
                ModelMeter(name: $0.name, meter: meter(shown == nil ? nil : $0.bucket, weekly: true))
            }
            return AccountRow(id: account.accountId, name: names[account.accountId] ?? "Account \(account.accountId.prefix(8))",
                              isCurrent: account.accountId == current?.account,
                              isTarget: account.accountId == target, isDisabled: busy,
                              session: meter(shown?.session), week: meter(shown?.week, weekly: true), models: models,
                              failureReason: entry?.failure?.reason,
                              tooltip: tooltip.joined(separator: "\n"), email: account.email,
                              isCLI: cli?.identity.map { $0.account == account.accountId && $0.org == account.orgId } ?? false,
                              isOutOfWeek: shown?.week.map { $0.isAtLimit && ($0.resetsAt ?? .distantPast) > now } ?? false,
                              limitResets: shown?.limitResets?.filter { ($0.expiresAt ?? .distantFuture) > now } ?? [])
        }
        .sorted { nameOrder(($0.name, $0.id), ($1.name, $1.id)) }

        let checked = usage.values.compactMap(\.checked).max()
        let updated = checked.map { date -> String in
            let minutes = Int(now.timeIntervalSince(date) / 60)
            return minutes < 1 ? "updated just now" : "updated \(minutes) min ago"
        }
        let cliNote: String?
        switch cli {
        case nil: cliNote = nil
        case .signedOut?: cliNote = "CLI: signed out"
        case .account?: cliNote = rows.contains(where: \.isCLI) ? nil : "CLI: not on a saved account"
        }
        return PanelState(rows: rows, busy: busy, updated: updated, cliNote: cliNote)
    }
}
