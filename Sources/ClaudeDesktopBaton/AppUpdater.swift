import AppKit
import BatonCore
import Observation
import Sparkle

/// Finds and installs updates of this app with Sparkle (docs/decisions/app-updates.md).
/// Background checks never open a window: they set the update notice, and the update window
/// opens only from the panel's Install… button or Check for Updates….
@MainActor @Observable
final class AppUpdater: NSObject {
    private(set) var notice = UpdateNotice()
    /// Whether an update may quit and relaunch the app right now; set by the panel model.
    @ObservationIgnored var mayRelaunch: () -> Bool = { true }
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    /// Sparkle's go-ahead to relaunch (or to install a silently downloaded update), held while a switch runs.
    @ObservationIgnored private var heldRelaunch: (() -> Void)?

    /// Starts the updater and checks once now; Sparkle then checks about once a day.
    /// A build without a feed (`swift run`, an unbundled binary) has no updater.
    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        controller.startUpdater()
        controller.updater.checkForUpdatesInBackground()
    }

    /// Opens the update window: the found update, "up to date", or the error.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func panelOpened() { notice.panelOpened() }

    /// Lets a held relaunch go ahead once no switch or switch alert is in the way.
    func resumeIfAllowed() {
        guard let relaunch = heldRelaunch, mayRelaunch() else { return }
        heldRelaunch = nil
        relaunch()
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem,
                 state: SPUUserUpdateState) {
        switch choice {
        case .skip: notice.chose(.skip)
        case .install: notice.chose(.install)
        case .dismiss: notice.chose(.dismiss)
        @unknown default: break
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        notice.noUpdateFound()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !mayRelaunch() else { return false }
        heldRelaunch = installHandler
        return true
    }

    /// With "Automatically download and install updates" on, install as soon as nothing is in the way
    /// instead of waiting for a quit that a login-item app rarely sees.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        heldRelaunch = immediateInstallHandler
        resumeIfAllowed()
        return true
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Background checks are shown as the update notice, not as a window.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            notice.found(version: version, userIsLooking: handleShowingUpdate)
        }
    }
}
