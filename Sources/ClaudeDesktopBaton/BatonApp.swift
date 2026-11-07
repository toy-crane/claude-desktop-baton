import BatonCore
import SwiftUI

struct BatonApp: App {
    @State private var model = PanelModel()

    init() {
        let model = _model.wrappedValue
        DispatchQueue.main.async { model.start() }
    }

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
            if model.isBusy {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: true)
                    .accessibilityLabel("Claude Desktop Baton: switching")
            } else if model.updater.notice.showsDot {
                Image(nsImage: AppIcon.menuBarWithDot)
                    .accessibilityLabel("Claude Desktop Baton: update available")
            } else {
                Image(nsImage: AppIcon.menuBar)
                    .accessibilityLabel("Claude Desktop Baton")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
