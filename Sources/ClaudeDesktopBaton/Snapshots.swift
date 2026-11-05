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
    cases.append(("switching", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .switching(accountId: b), now: now)))
    usage[b] = UsageEntry(failure: .offline, lastAttempt: now)
    cases.append(("usage-error", PanelState.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now)))

    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    // The menu bar icon on a light and a dark bar, at 2x.
    for (name, bar, ink) in [("menubar-light", NSColor(white: 0.93, alpha: 1), NSColor.black), ("menubar-dark", NSColor(white: 0.16, alpha: 1), NSColor.white)] {
        let canvas = NSImage(size: NSSize(width: 44, height: 24), flipped: false) { rect in
            bar.setFill(); rect.fill()
            let icon = AppIcon.menuBar.copy() as! NSImage
            icon.isTemplate = false
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r); ink.set(); r.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: 13, y: 3, width: 18, height: 18))
            return true
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 176, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        canvas.draw(in: NSRect(x: 0, y: 0, width: 176, height: 96))
        NSGraphicsContext.restoreGraphicsState()
        let file = folder.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        print(file.path)
    }

    // The alerts that replace in-panel switching messages, drawn without showing them.
    let alerts: [(String, AlertContent)] = [
        ("alert-confirm", Alerts.confirmSwitch(to: "Acme · sam", working: 2)),
        ("alert-failed", Alerts.switchFailed(to: "Acme · jordan", message: "Claude opened a different account. The saved sign-in may have expired; sign in to it in Claude and it is saved again.", putBack: "Acme · alex")),
        ("alert-sync", Alerts.syncSkipped(to: "Acme · sam", reason: "only 0 of 2 session files look familiar")),
    ]
    for (name, content) in alerts {
        let alert = NSAlert()
        alert.icon = AppIcon.image(size: 128)
        alert.messageText = content.title
        alert.informativeText = content.message
        content.buttons.forEach { alert.addButton(withTitle: $0) }
        alert.layout()
        guard let view = alert.window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: rep)
        let file = folder.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        print(file.path)
    }
    for (name, state) in cases {
        for scheme in [ColorScheme.light, .dark] {
            let view = PanelView(state: state, forSnapshot: true).environment(\.colorScheme, scheme)
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
