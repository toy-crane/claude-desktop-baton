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
}

public struct AccountRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isCurrent: Bool
    public let isTarget: Bool
    public let isDisabled: Bool
    public let session: Meter
    public let week: Meter
    /// Time until a reached limit resets, shown beside the name.
    public let resetNote: String?
    /// Why usage is unavailable, shown on hover beside the name.
    public let failureReason: String?
    public let tooltip: String
    public let email: String?
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
        message: "Claude reopened signed out on this Mac. Sign in to another account in Claude; it is saved automatically.",
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
    /// Every other saved account, in the order they were saved.
    public var switchTo: [AccountRow] { rows.filter { !$0.isCurrent } }
    public let busy: Bool
    /// "updated 1 min ago", for the "⋯" menu.
    public let updated: String?

    public static func make(accounts: [SavedAccount], current: Identity?, usage: [String: UsageEntry],
                            phase: Phase, now: Date) -> PanelState {
        let names = displayNames(accounts)
        var target: String?
        let busy: Bool
        switch phase {
        case .idle: busy = false
        case .switching(let id): busy = true; target = id
        case .adding: busy = true
        }

        func meter(_ bucket: Usage.Bucket?) -> Meter {
            guard let bucket else { return Meter(fraction: 0, text: "—", atLimit: false) }
            return Meter(fraction: bucket.used / 100, text: UsageText.percent(bucket.used), atLimit: bucket.isAtLimit)
        }
        func when(_ date: Date?) -> String {
            guard let date else { return "unknown" }
            return date.formatted(date: Calendar.current.isDate(date, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened)
        }

        let rows = accounts.map { account -> AccountRow in
            let entry = usage[account.accountId]
            let shown = entry?.failure == nil ? entry?.usage : nil
            let limited = [shown?.session, shown?.week].compactMap { $0 }.filter(\.isAtLimit)
            let resetNote = limited.compactMap(\.resetsAt).min().map { UsageText.until($0, from: now) }
            var tooltip = [account.email ?? account.accountId]
            if let shown {
                tooltip.append("Session resets \(when(shown.session?.resetsAt)) · Week resets \(when(shown.week?.resetsAt))")
            }
            return AccountRow(id: account.accountId, name: names[account.accountId] ?? "Account \(account.accountId.prefix(8))",
                              isCurrent: account.accountId == current?.account,
                              isTarget: account.accountId == target, isDisabled: busy,
                              session: meter(shown?.session), week: meter(shown?.week),
                              resetNote: resetNote, failureReason: entry?.failure?.reason,
                              tooltip: tooltip.joined(separator: "\n"), email: account.email)
        }

        let checked = usage.values.compactMap(\.checked).max()
        let updated = checked.map { date -> String in
            let minutes = Int(now.timeIntervalSince(date) / 60)
            return minutes < 1 ? "updated just now" : "updated \(minutes) min ago"
        }
        return PanelState(rows: rows, busy: busy, updated: updated)
    }
}
