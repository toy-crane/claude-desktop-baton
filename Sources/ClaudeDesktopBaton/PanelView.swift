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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        VStack(spacing: 0) {
            if let signedIn = state.signedIn {
                SectionLabel(text: "Signed in", palette: p)
                AccountBlock(row: signedIn, actions: actions, prominent: true)
                    .padding(.horizontal, 6).padding(.bottom, 6)
                Rectangle().fill(p.border).frame(height: 1)
            }
            if !state.switchTo.isEmpty {
                SectionLabel(text: "Switch to", palette: p)
            }
            VStack(spacing: 2) {
                ForEach(state.switchTo) { row in
                    AccountBlock(row: row, actions: actions)
                }
                if state.rows.isEmpty {
                    Text("No saved accounts yet. Sign in to Claude, or add an account.")
                        .font(.system(size: 12)).foregroundStyle(p.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
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
            .padding(.horizontal, 16).padding(.top, 9).padding(.bottom, 2)
    }
}

struct AccountBlock: View {
    let row: AccountRow
    let actions: PanelActions
    var prominent = false
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if row.isTarget { lead(p) }
                Text(row.name).font(.system(size: prominent ? 15 : 13, weight: prominent ? .semibold : .medium))
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
                Text(email).font(.system(size: 11.5)).foregroundStyle(p.muted).lineLimit(1).padding(.leading, 14).padding(.top, -4)
            }
            meter("Session", row.session, p)
            meter("Week", row.week, p)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering && !row.isCurrent && !row.isDisabled ? p.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !row.isDisabled && !row.isCurrent { actions.select(row.id) } }
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

    private func meter(_ label: String, _ meter: Meter, _ p: Palette) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(p.muted).frame(width: 54, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule().fill(meter.atLimit ? p.danger : p.ink).frame(width: geometry.size.width * min(max(meter.fraction, 0), 1))
                }
            }
            .frame(height: 4)
            Text(meter.text).font(.system(size: 11.5, design: .monospaced)).monospacedDigit()
                .foregroundStyle(meter.atLimit ? p.danger : p.ink)
                .frame(width: 38, alignment: .trailing)
            // Time until this limit resets; the column keeps its width so every bar ends at the same place.
            Text(meter.reset ?? "").font(.system(size: 11, design: .monospaced)).monospacedDigit()
                .foregroundStyle(p.muted).lineLimit(1)
                .frame(width: 48, alignment: .trailing)
                .help(meter.reset.map { "\(label) resets in \($0)" } ?? "")
        }
        .padding(.leading, 14)
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
