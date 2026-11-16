import BatonCore
import SwiftUI

struct LimitResetBadge: View {
    /// How far the click target reaches past the drawn border on every side. The
    /// badge sits on top of a block whose whole area switches accounts, so a near
    /// miss has to land on the badge rather than on the switch.
    static let safeArea: CGFloat = 5

    let row: AccountRow
    @Binding var expanded: Bool
    let palette: Palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var label: LimitResetBadgeLabel { LimitResetBadgeLabel(count: row.limitResetCount) }

    /// The row underneath is hovered at the same moment the pointer reaches the
    /// badge, so a fill of `palette.hover` would read as no feedback at all.
    private var fill: Color {
        if hovering { return palette.track }
        return expanded ? palette.hover : .clear
    }

    var body: some View {
        Button {
            expanded.toggle()
            // A click focuses the badge on macOS. Releasing it again keeps the
            // accent border for keyboard focus, which is what it is there for.
            focused = false
        } label: {
            label
                .background(fill, in: .rect(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Color.accentColor : palette.border))
                // A second ring just outside the border, so keyboard focus reads
                // as more than a change of hue on a one-point line.
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1)
                        .padding(-1)
                        .opacity(focused ? 1 : 0)
                }
                .padding(Self.safeArea)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .focusable(interactions: .edit)
        .focused($focused)
        // The system ring would trace the safe area, a visibly wider shape than
        // the badge. The border above is the badge's own focus marking.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .onKeyPress(keys: [.space, .return]) { _ in
            expanded.toggle()
            return .handled
        }
        .accessibilityLabel("\(label.title) for \(row.name)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

/// Also reserves room for the button in the row underneath the overlay. This is
/// the badge's drawn size; its click target is `LimitResetBadge.safeArea` wider.
struct LimitResetBadgeLabel: View {
    let count: UInt64

    var title: String { count == 1 ? "1 reset" : "\(count.formatted()) resets" }

    var body: some View {
        Text(title)
            .font(.system(size: 10))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .fixedSize()
    }
}

struct LimitResetDetails: View {
    let resets: [Usage.LimitReset]
    let palette: Palette

    var body: some View {
        Divider()
            .overlay(palette.border)
            .padding(.bottom, 6)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(resets.enumerated()), id: \.offset) { _, reset in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(reset.name) ×\(reset.remaining)")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let expiry = reset.expiresAt {
                        Text("Expires \(expiry.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .foregroundStyle(palette.muted)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }
                }
            }
        }
        .font(.system(size: 10.5))
    }
}
