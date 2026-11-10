import BatonCore
import SwiftUI

struct BatonApp: App {
    @State private var model = PanelModel()

    init() {
        let model = _model.wrappedValue
        DispatchQueue.main.async { model.start() }
    }

    /// The update notice's dot, drawn on whichever menu bar item is showing.
    private var updateDot: Bool { model.updater.notice.showsDot }

    var body: some Scene {
        MenuBarExtra {
            PanelView(state: model.state, launchAtLogin: model.launchAtLogin, commandLineInstalled: model.commandLineInstalled,
                      update: model.updater.notice.version,
                      actions: PanelActions(
                select: model.select, addAccount: model.addAccount, requestRemove: model.requestRemove,
                setLaunchAtLogin: model.setLaunchAtLogin, installCommandLine: model.installCommandLine,
                checkForUpdates: model.checkForUpdates,
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
                Image(nsImage: MenuBarMeter.image(usage, updateDot: updateDot))
                    .accessibilityLabel(updateDot ? usage.accessibility + ", update available" : usage.accessibility)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
