import AppKit
import SwiftUI

/// The app icon: a white relay baton across an ink squircle, in the panel's monochrome.
struct AppIconView: View {
    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                    .padding(s * 0.1)
                    .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.012)
                // The baton, with a dark grip band where the hand-off happens.
                ZStack {
                    Capsule().fill(Color.white).frame(width: s * 0.56, height: s * 0.13)
                    Rectangle().fill(Color(white: 0.1)).frame(width: s * 0.035, height: s * 0.13)
                        .offset(x: -s * 0.06)
                    Rectangle().fill(Color(white: 0.1)).frame(width: s * 0.035, height: s * 0.13)
                        .offset(x: s * 0.06)
                }
                .clipShape(Capsule().size(width: s * 0.56, height: s * 0.13).offset(x: 0, y: 0))
                .rotationEffect(.degrees(-45))
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

@MainActor
enum AppIcon {
    static func image(size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconView().frame(width: size, height: size))
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Writes an .iconset folder for `iconutil`.
    static func writeIconset(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(base * scale)
                guard let image = image(size: pixels), let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try? png.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}

extension AppIcon {
    /// The menu bar icon: the same baton as the app icon, as a template image so macOS tints it
    /// for light and dark menu bars and for the highlighted state.
    static let menuBar = menuBarImage(dot: false)

    /// The menu bar icon with the update notice's dot, set off from the baton by a gap.
    static let menuBarWithDot = menuBarImage(dot: true)

    private static func menuBarImage(dot: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: .pi / 4)
            let length: CGFloat = 16.5, thickness: CGFloat = 5
            let body = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
            context.addPath(CGPath(roundedRect: body, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            // The grip bands where the hand-off happens.
            context.setBlendMode(.clear)
            for x in [-2.6, 1.4] as [CGFloat] {
                context.fill(CGRect(x: x, y: -thickness, width: 1.2, height: thickness * 2))
            }
            context.restoreGState()
            if dot {
                // Top-left, the corner the diagonal baton leaves empty.
                let center = CGPoint(x: rect.minX + 3.4, y: rect.maxY - 3.4)
                context.setBlendMode(.clear)
                context.fillEllipse(in: CGRect(x: center.x - 4.2, y: center.y - 4.2, width: 8.4, height: 8.4))
                context.setBlendMode(.normal)
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: CGRect(x: center.x - 2.8, y: center.y - 2.8, width: 5.6, height: 5.6))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = dot ? "Claude Desktop Baton: update available" : "Claude Desktop Baton"
        return image
    }

    /// Frames of the turning-arrows icon, one full clockwise turn. `MenuBarExtra` flattens a label
    /// into one still image, so a symbol effect never moves there; the label swaps these images instead.
    static let spinnerFrameCount = 10
    static let spinner: [NSImage] = (0..<spinnerFrameCount).map { spinnerImage(turn: Double($0) / Double(spinnerFrameCount)) }

    private static func spinnerImage(turn: Double) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        // A fixed canvas, so the item keeps one width whatever the angle.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let symbol, let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: -turn * 2 * .pi)   // negative: clockwise in a bottom-left-origin context
            let size = symbol.size
            symbol.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
