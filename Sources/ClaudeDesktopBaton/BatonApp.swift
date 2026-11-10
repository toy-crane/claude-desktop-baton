import BatonCore
import SwiftUI

struct BatonApp: App {
    /// One model for the app's life, owned here rather than by `@State`: read in `init`, a `@State`
    /// value is not the instance SwiftUI later hands to `body`, so the model that was started was
    /// released at once and the panel showed one that never loaded the saved accounts.
    private static let shared = PanelModel()
    private var model: PanelModel { Self.shared }

    init() {
        DispatchQueue.main.async { Self.shared.start() }
    }

    /// The update notice's dot, drawn on whichever menu bar item is showing.
    private var updateDot: Bool { model.updater.notice.showsDot }

    var body: some Scene {
        MenuBarExtra {
            PanelView(state: model.state, launchAtLogin: model.launchAtLogin, commandLineInstalled: model.commandLineInstalled,
                      update: model.updater.notice.version, menuBarStyle: model.menuBarStyle,
                      actions: PanelActions(
                select: model.select, addAccount: model.addAccount, requestRemove: model.requestRemove,
                setLaunchAtLogin: model.setLaunchAtLogin, installCommandLine: model.installCommandLine,
                checkForUpdates: model.checkForUpdates, setMenuBarStyle: model.setMenuBarStyle,
                about: model.showAbout, quit: model.quit))
            .onAppear { model.panelOpened() }
        } label: {
            switch model.menuBar {
            case .switching:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: true)
                    .accessibilityLabel("Claude Desktop Baton: switching")
            case .icon:
                Image(nsImage: updateDot ? AppIcon.menuBarWithDot : AppIcon.menuBar)
                    .accessibilityLabel(updateDot ? "Claude Desktop Baton: update available" : "Claude Desktop Baton")
            case .usage(let usage):
                Image(nsImage: MenuBarMeter.image(usage, style: model.menuBarStyle, updateDot: updateDot))
                    .accessibilityLabel(updateDot ? usage.accessibility + ", update available" : usage.accessibility)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
