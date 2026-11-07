import Foundation

/// What the user chose in the update window.
public enum UpdateChoice: Equatable, Sendable {
    case skip, dismiss, install
}

/// The update notice: the "Update available" row in the panel and the dot on the menu bar icon.
/// Kept free of Sparkle and UI code so the rules can be tested.
public struct UpdateNotice: Equatable, Sendable {
    /// The version the panel row offers; nil hides the row.
    public private(set) var version: String?
    /// Whether the menu bar icon carries the dot.
    public private(set) var showsDot = false

    public init() {}

    /// A newer version was found. `userIsLooking` is true when the update window shows it right away
    /// (a check the user started), so there is nothing to draw their attention to.
    public mutating func found(version: String, userIsLooking: Bool) {
        if userIsLooking {
            showsDot = false
        } else if version != self.version {
            showsDot = true
        }
        self.version = version
    }

    /// The panel opened.
    public mutating func panelOpened() {
        if version != nil { showsDot = false }
    }

    /// Skipping hides the notice until a newer version; Remind Me Later and Install keep the row.
    public mutating func chose(_ choice: UpdateChoice) {
        if choice == .skip { self = UpdateNotice() }
    }

    /// A check finished without a newer version.
    public mutating func noUpdateFound() {
        self = UpdateNotice()
    }
}

/// When an update may quit and relaunch the app.
public enum UpdateGate {
    /// Never while a switch or an added account's sign-in is in progress, nor while a switch alert is open:
    /// a restart then can leave Claude closed or signed in to the wrong account.
    public static func mayRelaunch(phase: Phase, alertOpen: Bool) -> Bool {
        phase == .idle && !alertOpen
    }
}
