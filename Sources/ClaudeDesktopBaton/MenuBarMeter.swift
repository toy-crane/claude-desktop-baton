import AppKit
import BatonCore

/// The menu bar item while usage is known: a two-bar meter (Session on top, Week as a hairline
/// below) and the text, drawn as one template image so macOS tints it for light and dark menu
/// bars and for the highlighted state. A menu bar label cannot draw arbitrary SwiftUI shapes.
@MainActor
enum MenuBarMeter {
    static let height: CGFloat = 18
    static let meterWidth: CGFloat = 18
    static let spacing: CGFloat = 4

    private static var cache: (MenuBarUsage, NSImage)?

    static func image(_ usage: MenuBarUsage) -> NSImage {
        if let cache, cache.0 == usage { return cache.1 }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let strength: CGFloat = usage.dimmed ? 0.4 : 1
        let text = NSAttributedString(string: usage.text, attributes: [
            .font: font, .foregroundColor: NSColor.black.withAlphaComponent(strength),
        ])
        let textSize = text.size()
        // At least as wide as "100%", so the item does not shift as the percent changes; a reset time may widen it.
        let widest = NSAttributedString(string: "100%", attributes: [.font: font]).size().width
        let size = NSSize(width: meterWidth + spacing + ceil(max(textSize.width, widest)), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            let top: CGFloat = 5, bottom: CGFloat = 1.5, gap: CGFloat = 2
            let base = (height - (top + gap + bottom)) / 2
            bar(fraction: usage.week, y: base, thickness: bottom, strength: strength)
            bar(fraction: usage.session, y: base + bottom + gap, thickness: top, strength: strength)
            text.draw(at: NSPoint(x: meterWidth + spacing, y: (height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = usage.accessibility
        cache = (usage, image)
        return image
    }

    /// A faint track with the used part filled from the left.
    private static func bar(fraction: Double, y: CGFloat, thickness: CGFloat, strength: CGFloat) {
        let track = NSRect(x: 0, y: y, width: meterWidth, height: thickness)
        let radius = min(thickness / 2, 2)
        NSColor.black.withAlphaComponent(0.28 * strength).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let width = meterWidth * min(max(fraction, 0), 1)
        guard width > 0 else { return }
        NSColor.black.withAlphaComponent(strength).setFill()
        let used = NSRect(x: 0, y: y, width: width, height: thickness)
        let usedRadius = min(radius, width / 2)
        NSBezierPath(roundedRect: used, xRadius: usedRadius, yRadius: usedRadius).fill()
    }
}
