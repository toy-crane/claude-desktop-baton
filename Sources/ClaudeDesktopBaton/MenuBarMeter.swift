import AppKit
import BatonCore

/// The menu bar item while usage is known, in the layout chosen in the "⋯" menu: label columns,
/// a two-bar meter with the Session percent, or a two-line stack. Drawn as one template image so
/// macOS tints it for light and dark menu bars and for the highlighted state. A menu bar label
/// cannot draw arbitrary SwiftUI shapes.
@MainActor
enum MenuBarMeter {
    static let height: CGFloat = 22
    static let meterWidth: CGFloat = 18
    static let spacing: CGFloat = 4

    /// Room for the update notice's dot after the usage.
    static let dotWidth: CGFloat = 7

    private static var cache: (MenuBarUsage, MenuBarStyle, Bool, NSImage)?

    /// What one layout draws: its width, and a closure that draws it with its left edge at `x`.
    private struct Drawing {
        let width: CGFloat
        /// Where the update dot goes: right after what is actually drawn, not after reserved room.
        let inkWidth: CGFloat
        let draw: (CGFloat) -> Void
    }

    /// `updateDot` adds the update notice's dot at the top right, after the usage.
    static func image(_ usage: MenuBarUsage, style: MenuBarStyle = MenuBarStyle(), updateDot: Bool = false) -> NSImage {
        if let cache, cache.0 == usage, cache.1 == style, cache.2 == updateDot { return cache.3 }
        let strength: CGFloat = usage.dimmed ? 0.4 : 1
        let body: Drawing
        switch style.layout {
        case .columns: body = columns(usage, strength)
        case .bars: body = bars(usage, strength)
        case .stack: body = stack(usage, strength)
        }
        let icon = style.content == .iconAndUsage ? AppIcon.menuBar : nil
        let lead = icon.map { $0.size.width + 5 } ?? 0
        let size = NSSize(width: lead + body.width + (updateDot ? dotWidth : 0), height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            if let icon {
                // Always full strength: the baton is the app, not a reading that can go stale.
                icon.draw(in: NSRect(x: 0, y: (height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            }
            body.draw(lead)
            if updateDot {
                // Always full strength: the notice is current even when the usage is dimmed.
                NSColor.black.setFill()
                let diameter: CGFloat = 5
                NSBezierPath(ovalIn: NSRect(x: lead + body.inkWidth + 1.5, y: height - diameter - 4,
                                            width: diameter, height: diameter)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = usage.accessibility
        cache = (usage, style, updateDot, image)
        return image
    }

    private static func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.black.withAlphaComponent(alpha),
        ])
    }

    /// Session and Week side by side: a small label over each percent.
    private static func columns(_ usage: MenuBarUsage, _ strength: CGFloat) -> Drawing {
        let gap: CGFloat = 9
        // At least as wide as "100%", so the item does not shift as a percent changes; a reset time may widen it.
        let widest = text("100%", size: 11.5, weight: .medium, alpha: 1).size().width
        let cells = usage.limits.map { limit -> (NSAttributedString, NSAttributedString, CGFloat) in
            let label = text(limit.label, size: 8, weight: .semibold, alpha: 0.62 * strength)
            let value = text(limit.columnText, size: 11.5, weight: .medium, alpha: strength)
            return (label, value, ceil(max(label.size().width, value.size().width, widest)))
        }
        let width = cells.reduce(0) { $0 + $1.2 } + gap * CGFloat(max(cells.count - 1, 0))
        return Drawing(width: width, inkWidth: width) { origin in
            var x = origin
            for (label, value, cellWidth) in cells {
                label.draw(at: NSPoint(x: x + (cellWidth - label.size().width) / 2, y: 12.5))
                value.draw(at: NSPoint(x: x + (cellWidth - value.size().width) / 2, y: -0.5))
                x += cellWidth + gap
            }
        }
    }

    /// The two-bar meter (Session on top, Week as a hairline below) and the Session percent.
    private static func bars(_ usage: MenuBarUsage, _ strength: CGFloat) -> Drawing {
        let value = text(usage.text, size: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular, alpha: strength)
        let valueSize = value.size()
        let widest = text("100%", size: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular, alpha: 1).size().width
        let width = meterWidth + spacing + ceil(max(valueSize.width, widest))
        return Drawing(width: width, inkWidth: meterWidth + spacing + ceil(valueSize.width)) { origin in
            let top: CGFloat = 5, bottom: CGFloat = 1.5, gap: CGFloat = 2
            let base = (height - (top + gap + bottom)) / 2
            bar(fraction: usage.week, x: origin, y: base, thickness: bottom, strength: strength)
            bar(fraction: usage.session, x: origin, y: base + bottom + gap, thickness: top, strength: strength)
            value.draw(at: NSPoint(x: origin + meterWidth + spacing, y: (height - valueSize.height) / 2))
        }
    }

    /// Two lines, Session over Week: label, percent, and the time until the limit resets.
    private static func stack(_ usage: MenuBarUsage, _ strength: CGFloat) -> Drawing {
        let size: CGFloat = 9.5, gap: CGFloat = 4
        let rows = usage.limits.map { limit in
            (text(limit.label, size: size, weight: .semibold, alpha: 0.62 * strength),
             text(limit.percent, size: size, weight: .medium, alpha: strength),
             limit.reset.map { text($0.replacingOccurrences(of: " ", with: ""), size: size, weight: .regular, alpha: 0.62 * strength) })
        }
        let labelWidth = ceil(rows.map { $0.0.size().width }.max() ?? 0)
        let percentWidth = ceil(max(rows.map { $0.1.size().width }.max() ?? 0,
                                    text("100%", size: size, weight: .medium, alpha: 1).size().width))
        let resetWidth = ceil(rows.compactMap { $0.2?.size().width }.max() ?? 0)
        let width = labelWidth + gap + percentWidth + (resetWidth > 0 ? gap + resetWidth : 0)
        return Drawing(width: width, inkWidth: width) { origin in
            for (index, row) in rows.enumerated() {
                let y: CGFloat = index == 0 ? 10.5 : 0
                row.0.draw(at: NSPoint(x: origin, y: y))
                row.1.draw(at: NSPoint(x: origin + labelWidth + gap + percentWidth - row.1.size().width, y: y))
                row.2?.draw(at: NSPoint(x: origin + labelWidth + gap + percentWidth + gap, y: y))
            }
        }
    }

    /// A faint track with the used part filled from the left.
    private static func bar(fraction: Double, x: CGFloat, y: CGFloat, thickness: CGFloat, strength: CGFloat) {
        let track = NSRect(x: x, y: y, width: meterWidth, height: thickness)
        let radius = min(thickness / 2, 2)
        NSColor.black.withAlphaComponent(0.28 * strength).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let width = meterWidth * min(max(fraction, 0), 1)
        guard width > 0 else { return }
        NSColor.black.withAlphaComponent(strength).setFill()
        let used = NSRect(x: x, y: y, width: width, height: thickness)
        let usedRadius = min(radius, width / 2)
        NSBezierPath(roundedRect: used, xRadius: usedRadius, yRadius: usedRadius).fill()
    }
}
