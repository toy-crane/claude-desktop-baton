import Foundation

/// The signed-in account's usage as the menu bar item shows it: a two-bar meter and a text.
public struct MenuBarUsage: Hashable, Sendable {
    /// Session (top bar) and Week (bottom bar) used, 0–1.
    public let session: Double
    public let week: Double
    /// The Session percent; once a limit stops the user, the time until they can use Claude again.
    public let text: String
    /// The values are not current: the last refresh failed, or none has succeeded yet.
    public let dimmed: Bool
    public let accessibility: String
    public init(session: Double, week: Double, text: String, dimmed: Bool, accessibility: String) {
        self.session = session; self.week = week; self.text = text; self.dimmed = dimmed; self.accessibility = accessibility
    }
}

/// What the menu bar item shows. Kept free of UI code so the rules can be tested.
public enum MenuBarLabel: Hashable, Sendable {
    /// The baton alone: nothing to show usage for.
    case icon
    /// A switch or an account add is in progress.
    case switching
    case usage(MenuBarUsage)

    public static func make(accounts: [SavedAccount], current: Identity?, usage: [String: UsageEntry],
                            phase: Phase, now: Date) -> MenuBarLabel {
        guard phase == .idle else { return .switching }
        guard let current, accounts.contains(where: { $0.accountId == current.account }) else { return .icon }
        let name = "Claude Desktop Baton"
        let entry = usage[current.account]
        // A failed refresh keeps the last usage received; it is dimmed until a refresh succeeds.
        guard let last = entry?.usage else {
            return .usage(MenuBarUsage(session: 0, week: 0, text: "—", dimmed: true, accessibility: "\(name): usage unavailable"))
        }
        let dimmed = entry?.failure != nil
        let reached = [last.session, last.week].compactMap { $0 }.filter(\.isAtLimit)
        let text: String
        var spoken: String
        if !reached.isEmpty, reached.allSatisfy({ $0.resetsAt != nil }) {
            // Usable again only when every reached limit has reset.
            let until = UsageText.until(reached.compactMap(\.resetsAt).max()!, from: now)
            text = "↻ \(until)"
            spoken = "\(name): limit reached, available again in \(until)"
        } else {
            text = reached.isEmpty ? last.session.map { UsageText.percent($0.used) } ?? "—" : "100%"
            spoken = "\(name): Session \(last.session.map { UsageText.percent($0.used) } ?? "unknown"), "
                + "Week \(last.week.map { UsageText.percent($0.used) } ?? "unknown")"
        }
        if dimmed { spoken += ", not current" }
        return .usage(MenuBarUsage(session: (last.session?.used ?? 0) / 100, week: (last.week?.used ?? 0) / 100,
                                   text: text, dimmed: dimmed, accessibility: spoken))
    }
}
