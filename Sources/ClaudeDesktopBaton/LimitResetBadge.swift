import BatonCore
import SwiftUI

struct LimitResetBadge: View {
    let row: AccountRow
    @Binding var expanded: Bool
    let palette: Palette
    @FocusState private var focused: Bool

    private var label: LimitResetBadgeLabel { LimitResetBadgeLabel(count: row.limitResetCount) }

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            label
                .background(expanded ? palette.hover : .clear, in: .rect(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Color.accentColor : palette.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .focusable(interactions: .edit)
        .focused($focused)
        .onKeyPress(keys: [.space, .return]) { _ in
            expanded.toggle()
            return .handled
        }
        .accessibilityLabel("\(label.title) for \(row.name)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}

/// Also reserves room for the button in the row underneath the overlay.
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
