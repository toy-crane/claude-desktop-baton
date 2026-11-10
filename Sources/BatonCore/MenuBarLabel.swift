import Foundation

/// What the menu bar item is made of, chosen in the panel's "⋯" menu.
public enum MenuBarContent: String, CaseIterable, Sendable {
    case icon, usage, iconAndUsage

    public var title: String {
        switch self {
        case .icon: "Icon"
        case .usage: "Usage"
        case .iconAndUsage: "Icon and usage"
        }
    }
}

/// How usage is laid out in the menu bar item.
public enum MenuBarLayout: String, CaseIterable, Sendable {
    /// Session and Week percent side by side, each under a small label.
    case columns
    /// A two-bar meter and the Session percent.
    case bars
    /// Two lines, each with its percent and the time until it resets.
    case stack

    public var title: String {
        switch self {
        case .columns: "Columns"
        case .bars: "Bars"
        case .stack: "Stack"
        }
    }
}

public struct MenuBarStyle: Hashable, Sendable {
    public var content: MenuBarContent
    public var layout: MenuBarLayout
    public init(content: MenuBarContent = .usage, layout: MenuBarLayout = .columns) {
        self.content = content; self.layout = layout
    }

    static let contentKey = "menuBarContent", layoutKey = "menuBarLayout"

    /// The saved choice; anything missing or unknown falls back to the default.
    public static func load(_ defaults: UserDefaults = .standard) -> MenuBarStyle {
        MenuBarStyle(content: defaults.string(forKey: contentKey).flatMap(MenuBarContent.init) ?? .usage,
                     layout: defaults.string(forKey: layoutKey).flatMap(MenuBarLayout.init) ?? .columns)
    }

    public func save(_ defaults: UserDefaults = .standard) {
        defaults.set(content.rawValue, forKey: Self.contentKey)
        defaults.set(layout.rawValue, forKey: Self.layoutKey)
    }
}

/// One limit as the columns and stack layouts write it.
public struct MenuBarLimit: Hashable, Sendable {
    /// "5H" for the Session (5-hour) limit, "WK" for the Week limit.
    public let label: String
    /// "62%", or a dash when the limit is unknown.
    public let percent: String
    /// Time until the limit resets, "1h 12m"; nil when unknown.
    public let reset: String?
    public let atLimit: Bool
    public init(label: String, percent: String, reset: String? = nil, atLimit: Bool = false) {
        self.label = label; self.percent = percent; self.reset = reset; self.atLimit = atLimit
    }
    /// What a column shows: the percent, or the time until a reached limit resets.
    public var columnText: String { atLimit ? reset.map { "↻ \($0)" } ?? "100%" : percent }
}

/// The signed-in account's usage as the menu bar item shows it: a two-bar meter and a text,
/// or each limit's label, percent and reset, depending on the layout.
public struct MenuBarUsage: Hashable, Sendable {
    /// Session (top bar) and Week (bottom bar) used, 0–1.
    public let session: Double
    public let week: Double
    /// The Session percent; once a limit stops the user, the time until they can use Claude again.
    public let text: String
    /// The values are not current: the last refresh failed, or none has succeeded yet.
    public let dimmed: Bool
    public let accessibility: String
    /// Session first, then Week, for the columns and stack layouts.
    public let limits: [MenuBarLimit]
    public init(session: Double, week: Double, text: String, dimmed: Bool, accessibility: String,
                limits: [MenuBarLimit] = MenuBarUsage.unknownLimits) {
        self.session = session; self.week = week; self.text = text; self.dimmed = dimmed; self.accessibility = accessibility
        self.limits = limits
    }

    public static let unknownLimits = [MenuBarLimit(label: "5H", percent: "—"), MenuBarLimit(label: "WK", percent: "—")]
}

/// What the menu bar item shows. Kept free of UI code so the rules can be tested.
public enum MenuBarLabel: Hashable, Sendable {
    /// The baton alone: nothing to show usage for.
    case icon
    /// A switch or an account add is in progress.
    case switching
    case usage(MenuBarUsage)

    /// With `content` set to the icon alone, usage is never shown.
    public static func make(accounts: [SavedAccount], current: Identity?, usage: [String: UsageEntry],
                            phase: Phase, now: Date, content: MenuBarContent = .usage) -> MenuBarLabel {
        guard phase == .idle else { return .switching }
        guard content != .icon, let current, accounts.contains(where: { $0.accountId == current.account }) else { return .icon }
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
        func limit(_ label: String, _ bucket: Usage.Bucket?) -> MenuBarLimit {
            guard let bucket else { return MenuBarLimit(label: label, percent: "—") }
            return MenuBarLimit(label: label, percent: UsageText.percent(bucket.used),
                                reset: bucket.resetsAt.flatMap { $0 > now ? UsageText.until($0, from: now) : nil },
                                atLimit: bucket.isAtLimit)
        }
        return .usage(MenuBarUsage(session: (last.session?.used ?? 0) / 100, week: (last.week?.used ?? 0) / 100,
                                   text: text, dimmed: dimmed, accessibility: spoken,
                                   limits: [limit("5H", last.session), limit("WK", last.week)]))
    }
}
