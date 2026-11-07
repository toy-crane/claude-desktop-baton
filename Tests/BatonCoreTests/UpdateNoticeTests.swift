import Testing
@testable import BatonCore

@Suite("Update notice")
struct UpdateNoticeTests {
    // Spec: a background check that finds a newer version shows the row with its version and the icon dot.
    @Test func aVersionFoundInTheBackgroundShowsTheRowAndTheDot() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        #expect(notice.version == "0.3.1")
        #expect(notice.showsDot)
    }

    @Test func withNothingFoundThereIsNoRowAndNoDot() {
        let notice = UpdateNotice()
        #expect(notice.version == nil)
        #expect(!notice.showsDot)
    }

    // Spec assumption (interim): the dot clears once the panel has been opened with the row showing; the row stays.
    @Test func openingThePanelClearsTheDotButKeepsTheRow() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.panelOpened()
        #expect(notice.version == "0.3.1")
        #expect(!notice.showsDot)
    }

    // Spec: a newer release replaces the version shown (and draws attention again).
    @Test func aNewerVersionReplacesTheRowAndBringsTheDotBack() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.panelOpened()
        notice.found(version: "0.3.2", userIsLooking: false)
        #expect(notice.version == "0.3.2")
        #expect(notice.showsDot)
    }

    // Risk: the daily check finds the same version again; the dot the user already saw must not come back.
    @Test func findingTheSameVersionAgainDoesNotBringTheDotBack() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.panelOpened()
        notice.found(version: "0.3.1", userIsLooking: false)
        #expect(notice.version == "0.3.1")
        #expect(!notice.showsDot)
    }

    // Spec: Skip This Version removes the dot and the row.
    @Test func skippingTheVersionRemovesTheRowAndTheDot() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.chose(.skip)
        #expect(notice.version == nil)
        #expect(!notice.showsDot)
    }

    // Spec: Remind Me Later closes the window and keeps the row.
    @Test func remindMeLaterKeepsTheRow() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.chose(.dismiss)
        #expect(notice.version == "0.3.1")
    }

    // Spec: the row stays until the update is installed or skipped; Install Update leaves it until the relaunch.
    @Test func choosingInstallKeepsTheRowUntilTheAppRelaunches() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.chose(.install)
        #expect(notice.version == "0.3.1")
    }

    @Test func aCheckThatFindsNoUpdateClearsTheNotice() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: false)
        notice.noUpdateFound()
        #expect(notice.version == nil)
        #expect(!notice.showsDot)
    }

    // An update shown in the update window right away already has the user's attention: row, no dot.
    @Test func anUpdateTheUserIsAlreadyLookingAtShowsTheRowWithoutTheDot() {
        var notice = UpdateNotice()
        notice.found(version: "0.3.1", userIsLooking: true)
        #expect(notice.version == "0.3.1")
        #expect(!notice.showsDot)
    }
}

@Suite("Update relaunch gate")
struct UpdateGateTests {
    @Test func anIdleAppWithNoAlertOpenMayRelaunch() {
        #expect(UpdateGate.mayRelaunch(phase: .idle, alertOpen: false))
    }

    // Spec: no relaunch while a switch is running, or while a switch alert (confirm, failed, Put Back) is open.
    @Test func neverDuringASwitch() {
        #expect(!UpdateGate.mayRelaunch(phase: .switching(accountId: "b"), alertOpen: false))
    }

    @Test func neverWhileASwitchAlertIsOpen() {
        #expect(!UpdateGate.mayRelaunch(phase: .idle, alertOpen: true))
    }

    // Risk: adding an account leaves Claude signed out while the app waits for the sign-in; a restart loses that wait.
    @Test func neverWhileAnAddedAccountIsBeingSignedIn() {
        #expect(!UpdateGate.mayRelaunch(phase: .adding, alertOpen: false))
    }
}
