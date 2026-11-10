import AppKit
import BatonCore
import SwiftUI

/// Renders the real panel view with sample accounts in each state, light and dark.
@MainActor
func renderSnapshots(to folder: URL) {
    let now = Date()
    let org = "0000000f-0000-4000-8000-00000000000f"
    func account(_ id: String, _ email: String, _ added: Double) -> SavedAccount {
        SavedAccount(accountId: id, orgId: org, email: email, orgName: "Acme", savedAt: added, addedAt: added,
                     signIn: SignIn(config: [:], cookieSchema: 24, cookies: []))
    }
    let a = "aaaaaaaa-0000-4000-8000-000000000001", b = "bbbbbbbb-0000-4000-8000-000000000002", c = "cccccccc-0000-4000-8000-000000000003"
    let accounts = [account(a, "alex@example.com", 1), account(b, "sam@example.com", 2), account(c, "jordan@example.com", 3)]
    var usage: [String: UsageEntry] = [
        a: UsageEntry(usage: Usage(session: .init(used: 62, resetsAt: now.addingTimeInterval(3600)), week: .init(used: 81, resetsAt: nil)), checked: now.addingTimeInterval(-60)),
        b: UsageEntry(usage: Usage(session: .init(used: 8, resetsAt: nil), week: .init(used: 34, resetsAt: nil)), checked: now.addingTimeInterval(-60)),
        c: UsageEntry(usage: Usage(session: .init(used: 100, resetsAt: now.addingTimeInterval(72 * 60 + 20)), week: .init(used: 97, resetsAt: nil)), checked: now.addingTimeInterval(-60)),
    ]
    let current = Identity(account: a, org: org)
    var cases: [(String, PanelState)] = []
    cases.append(("default", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now)))
    let updateCase = "update"
    cases.append((updateCase, PanelState.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now)))
    cases.append(("switching", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .switching(accountId: b), now: now)))
    cases.append(("cli", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now,
                                         cli: .account(Identity(account: b, org: org)), cliSaved: [a, b])))
    let remote = [RemoteSession(sessionId: "b2da6403-1087-5f10-929c-77c6fe7a8aaf",
                                folder: "/Users/sam/code/shop/.claude/worktrees/bridge-cse_01", name: "Plan the checkout flow"),
                  RemoteSession(sessionId: "5a1a77f5-8215-5a78-8cc7-db3f78c0e914",
                                folder: "/Users/sam/code/shop/.claude/worktrees/bridge-cse_02")]
    cases.append(("remote", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now, remote: remote)))
    usage[b] = UsageEntry(failure: .offline, lastAttempt: now)
    cases.append(("usage-error", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now)))

    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    // The menu bar item on a light and a dark bar, at 4x: the baton, and the usage meter in its states.
    func menuBar(_ image: NSImage, _ name: String) {
        for (theme, bar, ink) in [("light", NSColor(white: 0.93, alpha: 1), NSColor.black), ("dark", NSColor(white: 0.16, alpha: 1), NSColor.white)] {
            let width = image.size.width + 26
            let canvas = NSImage(size: NSSize(width: width, height: 24), flipped: false) { rect in
                bar.setFill(); rect.fill()
                let template = image.copy() as! NSImage
                template.isTemplate = false
                let tinted = NSImage(size: template.size, flipped: false) { r in
                    template.draw(in: r); ink.set(); r.fill(using: .sourceAtop); return true
                }
                tinted.draw(in: NSRect(x: 13, y: 3, width: image.size.width, height: image.size.height))
                return true
            }
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 4), pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            canvas.draw(in: NSRect(x: 0, y: 0, width: width * 4, height: 96))
            NSGraphicsContext.restoreGraphicsState()
            let file = folder.appendingPathComponent("\(name)-\(theme).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            print(file.path)
        }
    }
    menuBar(AppIcon.menuBar, "menubar")
    func bucket(_ used: Double, _ reset: TimeInterval?) -> Usage.Bucket { .init(used: used, resetsAt: reset.map(now.addingTimeInterval)) }
    let meterCases: [(String, UsageEntry?)] = [
        ("usage", UsageEntry(usage: Usage(session: bucket(42, 3600), week: bucket(18, 86_400)), checked: now)),
        ("usage-low", UsageEntry(usage: Usage(session: bucket(0.4, 3600), week: bucket(3, 86_400)), checked: now)),
        ("usage-high", UsageEntry(usage: Usage(session: bucket(91, 3600), week: bucket(64, 86_400)), checked: now)),
        ("usage-session-limit", UsageEntry(usage: Usage(session: bucket(100, 72 * 60 + 20), week: bucket(64, 86_400)), checked: now)),
        ("usage-week-limit", UsageEntry(usage: Usage(session: bucket(30, 3600), week: bucket(100, 2 * 86_400 + 3 * 3600)), checked: now)),
        ("usage-both-limits", UsageEntry(usage: Usage(session: bucket(100, 72 * 60), week: bucket(100, 2 * 86_400 + 3 * 3600)), checked: now)),
        ("usage-unavailable", UsageEntry(usage: Usage(session: bucket(42, 3600), week: bucket(18, 86_400)), failure: .offline, checked: now)),
        ("usage-none-yet", nil),
    ]
    for (name, entry) in meterCases {
        var entries = usage
        entries[a] = entry
        if case .usage(let shown) = MenuBarLabel.make(accounts: accounts, current: current, usage: entries, phase: .idle, now: now) {
            menuBar(MenuBarMeter.image(shown), "menubar-\(name)")
        }
    }
    // The update notice's dot, on the baton and on the usage meter.
    menuBar(AppIcon.menuBarWithDot, "menubar-update")
    if case .usage(let shown) = MenuBarLabel.make(accounts: accounts, current: current, usage: [a: meterCases[0].1!], phase: .idle, now: now) {
        menuBar(MenuBarMeter.image(shown, updateDot: true), "menubar-usage-update")
    }

    // The alerts that replace in-panel switching messages, drawn without showing them.
    let alerts: [(String, AlertContent)] = [
        ("alert-confirm", Alerts.confirmSwitch(to: "Acme · sam", working: 2)),
        ("alert-confirm-remote", Alerts.confirmSwitch(to: "Acme · sam", working: 0, remote: 2)),
        ("alert-failed", Alerts.switchFailed(to: "Acme · jordan", message: "Claude opened a different account. The saved sign-in may have expired; sign in to it in Claude and it is saved again.", putBack: "Acme · alex")),
        ("alert-sync", Alerts.syncSkipped(to: "Acme · sam", reason: "only 0 of 2 session files look familiar")),
        ("alert-cli", Alerts.cliNotFollowing(to: "Acme · jordan", cli: "Acme · sam")),
    ]
    // Each alert in light and dark for the README. NSAlert ignores dark mode when drawn off screen,
    // so this draws the same text in the macOS alert layout with SwiftUI.
    for (name, content) in alerts {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: AlertCard(content: content).environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
            try? png.write(to: file)
            print(file.path)
        }
    }
    for (name, state) in cases {
        for scheme in [ColorScheme.light, .dark] {
            let view = PanelView(state: state, update: name == updateCase ? "0.3.1" : nil, forSnapshot: true)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
            try? png.write(to: file)
            print(file.path)
        }
    }
}

/// A macOS-style alert drawn in SwiftUI, used only for README images.
struct AlertCard: View {
    let content: AlertContent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            if let icon = AppIcon.image(size: 128) {
                Image(nsImage: icon).resizable().frame(width: 64, height: 64).padding(.bottom, 14)
            }
            Text(content.title).font(.system(size: 13, weight: .bold)).padding(.bottom, 8)
            Text(content.message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).padding(.bottom, 16)
            let buttons = content.buttons
            if buttons.count == 2 && buttons.allSatisfy({ $0.count < 12 }) {
                HStack(spacing: 8) { ForEach(buttons.reversed(), id: \.self) { button($0, dark) } }
            } else {
                VStack(spacing: 8) { ForEach(buttons, id: \.self) { button($0, dark) } }
            }
        }
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(20)
        .frame(width: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(dark ? Color(white: 0.17) : Color(white: 0.97)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 1))
        .padding(10)
    }

    private func button(_ title: String, _ dark: Bool) -> some View {
        Text(title).font(.system(size: 13))
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(Capsule().fill(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)))
    }
}
