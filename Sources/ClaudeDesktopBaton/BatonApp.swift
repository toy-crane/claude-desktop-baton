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
                      actions: PanelActions(
                select: model.select, addAccount: model.addAccount, requestRemove: model.requestRemove,
                setLaunchAtLogin: model.setLaunchAtLogin, installCommandLine: model.installCommandLine,
                about: model.showAbout, quit: model.quit))
            .onAppear { model.panelOpened() }
        } label: {
            switch model.menuBar {
            case .switching:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: true)
                    .accessibilityLabel("Claude Desktop Baton: switching")
            case .icon:
                Image(nsImage: AppIcon.menuBar)
                    .accessibilityLabel("Claude Desktop Baton")
            case .usage(let usage):
                Image(nsImage: MenuBarMeter.image(usage))
                    .accessibilityLabel(usage.accessibility)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
