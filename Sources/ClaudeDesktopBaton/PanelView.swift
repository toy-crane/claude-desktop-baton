import BatonCore
import SwiftUI

/// Monochrome ink on a plain surface; red only for a reached limit and a failed switch.
struct Palette {
    let background, ink, muted, track, hover, border, danger: Color

    init(_ scheme: ColorScheme) {
        func rgb(_ hex: UInt32) -> Color {
            Color(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
        }
        if scheme == .dark {
            background = rgb(0x0a0a0a); ink = rgb(0xededed); muted = rgb(0xa1a1a1); track = rgb(0x262626)
            hover = rgb(0x181818); border = rgb(0x2a2a2a); danger = rgb(0xff6369)
        } else {
            background = rgb(0xffffff); ink = rgb(0x0a0a0a); muted = rgb(0x6b6b6b); track = rgb(0xececec)
            hover = rgb(0xf4f4f4); border = rgb(0xeaeaea); danger = rgb(0xe5484d)
        }
    }
}

struct PanelActions {
    var select: (String) -> Void = { _ in }
    var addAccount: () -> Void = {}
    var requestRemove: (String) -> Void = { _ in }
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var installCommandLine: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var setMenuBarStyle: (MenuBarStyle) -> Void = { _ in }
    var about: () -> Void = {}
    var quit: () -> Void = {}
}

struct PanelView: View {
    let state: PanelState
    var launchAtLogin = false
    var commandLineInstalled = false
    /// The newer version the update notice offers; nil hides its row.
    var update: String?
    var menuBarStyle = MenuBarStyle()
    var actions = PanelActions()
    /// Image snapshots cannot draw AppKit-backed menus; they show the menu's own label instead.
    var forSnapshot = false
    /// The account the pointer is over and would switch to; its hover highlight hides the hairlines around it.
    @State private var highlighted: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        VStack(spacing: 0) {
            if let signedIn = state.signedIn {
                SectionLabel(text: "Signed in", palette: p)
                AccountBlock(row: signedIn, actions: actions, prominent: true)
                    .padding(.horizontal, PanelSpacing.edge).padding(.bottom, PanelSpacing.edge)
                Rectangle().fill(p.border).frame(height: 1)
            }
            if !state.switchTo.isEmpty {
                SectionLabel(text: "Switch to", palette: p)
            }
            VStack(spacing: PanelSpacing.blocks) {
                ForEach(Array(state.switchTo.enumerated()), id: \.element.id) { index, row in
                    AccountBlock(row: row, actions: actions, highlighted: $highlighted,
                                 divider: index > 0 && highlighted != row.id && highlighted != state.switchTo[index - 1].id)
                }
                if state.rows.isEmpty {
                    Text("No saved accounts yet. Sign in to Claude, or add an account.")
                        .font(.system(size: 12)).foregroundStyle(p.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
            }
            .padding(.horizontal, PanelSpacing.edge)
            .padding(.bottom, PanelSpacing.edge)
            if let update {
                Rectangle().fill(p.border).frame(height: 1)
                updateRow(update, p)
            }
            Rectangle().fill(p.border).frame(height: 1)
            footer(p)
        }
        .frame(width: 300)
        .background(p.background)
        .foregroundStyle(p.ink)
    }

    /// The update notice's row: a newer version of this app is ready to install.
    private func updateRow(_ version: String, _ p: Palette) -> some View {
        HStack(spacing: 8) {
            Circle().fill(p.ink).frame(width: 6, height: 6)
            (Text("Update available").font(.system(size: 12.5))
                + Text(" · \(version)").font(.system(size: 12.5)).foregroundStyle(p.muted))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            Button("Install…", action: actions.checkForUpdates)
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(QuietButtonStyle(palette: p, prominent: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func footer(_ p: Palette) -> some View {
        HStack {
            Button(action: actions.addAccount) {
                HStack(spacing: 6) {
                    Text("+").font(.system(size: 15)).foregroundStyle(p.muted)
                    Text("Add account").font(.system(size: 12.5))
                }
            }
            .buttonStyle(QuietButtonStyle(palette: p))
            .disabled(state.busy)
            Spacer()
            if forSnapshot { moreLabel(p) } else { moreMenu(p) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func moreLabel(_ p: Palette) -> some View {
        Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(p.muted)
            .frame(width: 26, height: 22)
    }

    private func moreMenu(_ p: Palette) -> some View {
            Menu {
                if let updated = state.updated { Text(updated) }
                if let cliNote = state.cliNote { Text(cliNote) }
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: actions.setLaunchAtLogin))
                Menu("Menu bar") {
                    Picker("Show", selection: Binding(get: { menuBarStyle.content }, set: { content in
                        actions.setMenuBarStyle(MenuBarStyle(content: content, layout: menuBarStyle.layout))
                    })) {
                        ForEach(MenuBarContent.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Picker("Usage layout", selection: Binding(get: { menuBarStyle.layout }, set: { layout in
                        actions.setMenuBarStyle(MenuBarStyle(content: menuBarStyle.content, layout: layout))
                    })) {
                        ForEach(MenuBarLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .disabled(menuBarStyle.content == .icon)
                }
                Menu("Remove account") {
                    ForEach(state.rows) { row in Button(row.name) { actions.requestRemove(row.id) } }
                }
                .disabled(state.busy || state.rows.isEmpty)
                Button(commandLineInstalled ? "Command Line Tool Installed" : "Install Command Line Tool",
                       action: actions.installCommandLine)
                    .disabled(commandLineInstalled)
                Divider()
                Button("Check for Updates…", action: actions.checkForUpdates)
                Button("About Claude Desktop Baton", action: actions.about)
                Button("Quit", action: actions.quit).keyboardShortcut("q")
            } label: {
                moreLabel(p)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
    }
}

struct QuietButtonStyle: ButtonStyle {
    let palette: Palette
    var prominent = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, prominent ? 10 : 8)
            .padding(.vertical, prominent ? 3 : 5)
            .foregroundStyle(prominent ? palette.background : palette.ink)
            .background(RoundedRectangle(cornerRadius: prominent ? 6 : 7)
                .fill(prominent ? palette.ink : (hovering ? palette.hover : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(prominent ? .clear : palette.border, lineWidth: prominent ? 0 : 0))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionLabel: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelSpacing.edge + PanelSpacing.inset).padding(.top, PanelSpacing.inset).padding(.bottom, PanelSpacing.tight)
    }
}

/// The panel's spacing. Every account block uses these, so the signed-in account and the others
/// differ only in the size of the name.
enum PanelSpacing {
    /// The panel's edge.
    static let edge: CGFloat = 6
    /// Inside an account block, on every side.
    static let inset: CGFloat = 10
    /// Between a limit's text and its bar, a name and its email, and one block and the next.
    static let tight: CGFloat = 4
    /// Between a name and the row of limit columns.
    static let gap: CGFloat = 8
    /// Between limit columns.
    static let columnGap: CGFloat = 10
    /// Between one account block and the next, where a hairline sits.
    static let blocks: CGFloat = 2
    /// The most limit columns in a row; further limits wrap to the next row.
    static let maxColumns = 3
}

struct AccountBlock: View {
    let row: AccountRow
    let actions: PanelActions
    var prominent = false
    /// The id of the account whose highlight is showing; set while the pointer is over this block.
    var highlighted: Binding<String?> = .constant(nil)
    /// Draws a hairline along the block's top edge, separating it from the account above.
    var divider = false
    @Environment(\.colorScheme) private var scheme

    private var canSwitch: Bool { !row.isDisabled && !row.isCurrent }

    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if row.isTarget { lead(p) }
                Text(row.name).font(.system(size: prominent ? 15 : 13.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                if row.isCLI {
                    Text("CLI").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(p.muted)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.muted.opacity(0.6), lineWidth: 0.75))
                        .help("The Claude Code CLI is signed in to this account.")
                }
                if let reason = row.failureReason {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(p.muted).help(reason)
                }
                Spacer(minLength: 6)
            }
            if prominent, let email = row.email {
                Text(email).font(.system(size: 11.5)).foregroundStyle(p.muted).lineLimit(1)
                    .padding(.top, PanelSpacing.tight)
            }
            columns(p).padding(.top, PanelSpacing.gap)
        }
        .padding(PanelSpacing.inset)
        .background(RoundedRectangle(cornerRadius: 8).fill(highlighted.wrappedValue == row.id ? p.hover : .clear))
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(p.border).frame(height: 1).padding(.horizontal, PanelSpacing.inset).offset(y: -1)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside && canSwitch { highlighted.wrappedValue = row.id }
            else if highlighted.wrappedValue == row.id { highlighted.wrappedValue = nil }
        }
        .onTapGesture { if canSwitch { actions.select(row.id) } }
        .help(row.tooltip)
        .opacity(row.isDisabled && !row.isTarget ? 0.4 : 1)
    }

    @ViewBuilder private func lead(_ p: Palette) -> some View {
        if row.isTarget {
            Spinner(color: p.ink).frame(width: 9, height: 9).padding(.horizontal, -1.5)
        } else {
            Circle().fill(row.isCurrent ? p.ink : .clear).frame(width: 6, height: 6)
        }
    }

    /// Session, Week, then each model limit, side by side in equal-width columns; more than
    /// `maxColumns` wrap to a further row with the same column width.
    private func columns(_ p: Palette) -> some View {
        let limits: [(label: String, meter: Meter)] = [("Session", row.session), ("Week", row.week)]
            + row.models.map { ($0.name, $0.meter) }
        let perRow = min(limits.count, PanelSpacing.maxColumns)
        let rows = stride(from: 0, to: limits.count, by: perRow).map { Array(limits[$0..<min($0 + perRow, limits.count)]) }
        return VStack(alignment: .leading, spacing: PanelSpacing.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, chunk in
                HStack(alignment: .top, spacing: PanelSpacing.columnGap) {
                    ForEach(Array(chunk.enumerated()), id: \.offset) { _, limit in
                        column(limit.label, limit.meter, p)
                    }
                    ForEach(0..<(perRow - chunk.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
            }
        }
    }

    /// One limit: a small uppercase label, the percent used, its bar, and when it resets.
    private func column(_ label: String, _ meter: Meter, _ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.5)
                .foregroundStyle(p.muted).lineLimit(1).truncationMode(.tail)
            Text(meter.text).font(.system(size: 15, weight: .medium)).monospacedDigit()
                .foregroundStyle(meter.atLimit ? p.danger : p.ink).lineLimit(1)
                .padding(.top, 1).padding(.bottom, PanelSpacing.tight)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule().fill(meter.atLimit ? p.danger : p.ink).frame(width: geometry.size.width * min(max(meter.fraction, 0), 1))
                }
            }
            .frame(height: 4)
            if let reset = meter.reset {
                Text("\u{21BB} \(reset)").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(p.muted)
                    .lineLimit(1).truncationMode(.tail).padding(.top, PanelSpacing.tight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small ring that turns; drawn in SwiftUI so it matches the panel's ink and renders in snapshots.
struct Spinner: View {
    let color: Color
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}
