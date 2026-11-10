import Foundation
import Testing
@testable import BatonCore

private let A = ClaudeFixture.a
private let B = ClaudeFixture.b
private let C = ClaudeFixture.c
private let s1 = "11111111-1111-4111-8111-111111111111"

@Suite("Switching accounts", .serialized)
struct SwitcherTests {

    /// A signed in and saved; B saved earlier. Claude is running as A.
    private func twoSavedAccounts() throws -> (ClaudeFixture, SavedAccount) {
        let f = try ClaudeFixture(signedIn: B)
        let b = try f.saveSignedIn()
        try f.signIn(A, token: "tok-A")
        try f.saveSignedIn()
        return (f, b)
    }

    @Test func switchingPutsTheTargetSignInInPlaceAndClaudeConfirmsIt() async throws {
        let (f, b) = try twoSavedAccounts()

        let result = await f.switcher.switchTo(b)

        #expect(result.error == nil)
        #expect(f.configAccount == B)
        #expect(f.sessionKey == "sk-b")
        #expect(f.config["darkMode"] as? String == "system")
        #expect(f.otherCookie == "keep")
        #expect(f.fake.opened == 1)
    }

    // Remote Control sessions are listed by the account that started their server, so the sync has nothing
    // to copy: once Claude confirms the target, each is opened the way `/desktop` opens it.
    @Test func runningRemoteControlSessionsAreHandedToClaudeAfterItConfirmsTheTarget() async throws {
        let (f, b) = try twoSavedAccounts()
        try f.registerRemoteSession("aaaa1111-1111-4111-8111-111111111111", slot: 1)
        try f.registerRemoteSession("bbbb2222-2222-4222-8222-222222222222", slot: 2)

        let result = await f.switcher.switchTo(b)

        #expect(result.error == nil)
        #expect(f.fake.links.map(\.absoluteString).sorted() == ["claude://resume?session=aaaa1111-1111-4111-8111-111111111111",
                                                                 "claude://resume?session=bbbb2222-2222-4222-8222-222222222222"])
        #expect(result.remoteOpened.count == 2)
        #expect(f.configAccount == B)
    }

    @Test func aRemoteControlSessionClaudeAlreadyListsIsNotOpenedAgain() async throws {
        let (f, b) = try twoSavedAccounts()
        try f.registerRemoteSession(s1)
        try f.writeSession(A, s1, secondsAgo: 60)

        let result = await f.switcher.switchTo(b)

        #expect(result.error == nil)
        #expect(f.fake.links.isEmpty)
        #expect(f.hasSession(B, s1))
    }

    @Test func aFailedSwitchHandsNoRemoteControlSessionToClaude() async throws {
        let (f, b) = try twoSavedAccounts()
        try f.registerRemoteSession(s1)
        f.fake.loadsInstead = A

        let result = await f.switcher.switchTo(b)

        #expect(result.error != nil)
        #expect(f.fake.links.isEmpty)
        #expect(result.remoteOpened.isEmpty)
    }

    // AC1 / AC2: sessions are brought in line during the switch, while Claude is closed.
    @Test func sessionsAreSyncedWhileClaudeIsClosedBeforeItReopens() async throws {
        let (f, b) = try twoSavedAccounts()
        try f.writeSession(A, s1, secondsAgo: 60)
        var syncedBeforeOpen = false
        f.fake.onOpen = { syncedBeforeOpen = f.hasSession(B, s1) }

        let result = await f.switcher.switchTo(b)

        #expect(syncedBeforeOpen)
        #expect(result.sync?.created ?? 0 >= 1)
    }

    // Switching step 4: a token Claude refreshed since the last save is kept.
    @Test func outgoingAccountIsSavedAgainWithItsLatestSignIn() async throws {
        let (f, b) = try twoSavedAccounts()
        try f.signIn(A, token: "tok-A-refreshed")

        _ = await f.switcher.switchTo(b)

        #expect(f.store.load(A)?.signIn.config["oauth:tokenCacheV2"] == "tok-A-refreshed")
    }

    // Switching step 3: Claude that will not quit stops the switch with nothing changed.
    @Test func claudeThatStaysOpenLeavesEverythingUnchanged() async throws {
        let (f, b) = try twoSavedAccounts()
        try f.writeSession(A, s1, secondsAgo: 60)
        f.fake.refusesToQuit = true

        let result = await f.switcher.switchTo(b)

        #expect(result.error != nil)
        #expect(f.configAccount == A)
        #expect(!f.hasSession(B, s1))
        #expect(f.fake.opened == 0)
        // Review finding: nothing changed, so there is nothing to put back.
        #expect(!result.signInChanged)
    }

    // AC7
    @Test func targetThatFailsToLoadOffersThePreviousAccountAndPuttingItBackWorks() async throws {
        let (f, b) = try twoSavedAccounts()
        f.fake.loadsInstead = C

        let failed = await f.switcher.switchTo(b)

        #expect(failed.error != nil)
        #expect(failed.previous == Identity(account: A, org: ClaudeFixture.org))
        #expect(failed.signInChanged)

        f.fake.loadsInstead = nil
        let back = await f.switcher.switchTo(try #require(f.store.load(A)))
        #expect(back.error == nil)
        #expect(f.configAccount == A)
    }

    // AC12
    @Test func syncFailureDoesNotStopTheSwitch() async throws {
        let (f, b) = try twoSavedAccounts()
        for name in ["local_\(s1).json", "local_22222222-2222-4222-8222-222222222222.json"] {
            try Data("garbage".utf8).write(to: f.folder(A).appendingPathComponent(name))
        }

        let result = await f.switcher.switchTo(b)

        #expect(result.sync?.aborted != nil)
        #expect(result.error == nil)
        #expect(f.configAccount == B)
    }

    // AC10
    @Test func addAccountReopensClaudeSignedOutAndKeepsTheOutgoingAccount() async throws {
        let f = try ClaudeFixture(signedIn: A)
        try f.saveSignedIn()
        try f.signIn(A, token: "tok-A-refreshed")

        let result = await f.switcher.addAccount()

        #expect(result.error == nil)
        #expect(f.configAccount == nil)
        #expect(f.sessionKey == nil)
        #expect(f.otherCookie == "keep")
        #expect(f.config["darkMode"] as? String == "system")
        #expect(f.fake.opened == 1)
        #expect(f.store.load(A)?.signIn.config["oauth:tokenCacheV2"] == "tok-A-refreshed")
    }

    // AC9 / AC10
    @Test func unsavedSignedInAccountIsSavedAutomatically() throws {
        let f = try ClaudeFixture(signedIn: C)

        let saved = f.switcher.saveCurrentIfNew()

        #expect(saved?.accountId == C)
        #expect(f.store.load(C)?.signIn.config["oauth:tokenCacheV2"] == "tok-c")
    }

    // AC9: mid-switch, when Claude's log and stored sign-in disagree, nothing is saved.
    @Test func nothingIsSavedWhileTheLogAndSignInDisagree() throws {
        let f = try ClaudeFixture(signedIn: C)
        f.appendLog(B)

        #expect(f.switcher.saveCurrentIfNew() == nil)
        #expect(f.store.all().isEmpty)
    }

    // AC11
    @Test func removingAnAccountChangesOnlyTheSavedCopy() throws {
        let (f, b) = try twoSavedAccounts()
        try f.writeSession(B, s1, secondsAgo: 60)
        let before = try Data(contentsOf: f.claude.config)

        try f.store.remove(b.accountId)

        #expect(f.store.load(B) == nil)
        #expect(f.store.load(A) != nil)
        #expect(try Data(contentsOf: f.claude.config) == before)
        #expect(f.hasSession(B, s1))
    }

    // AC6: only sessions active in the signed-in folder within the last 2 minutes count as working.
    @Test func workingSessionsCountsRecentActivityInTheSignedInFolderOnly() throws {
        let f = try ClaudeFixture(signedIn: A)
        try f.writeSession(A, s1, secondsAgo: 30)
        try f.writeSession(A, "22222222-2222-4222-8222-222222222222", secondsAgo: 600)
        try f.writeSession(B, "33333333-3333-4333-8333-333333333333", secondsAgo: 5)

        #expect(f.switcher.workingSessions() == 1)
    }

    // AC6 (found on this Mac: Claude updates lastActivityAt only when a turn starts, while the
    // conversation file keeps being written during the turn): a long turn still counts as working.
    @Test func sessionInTheMiddleOfALongTurnCountsAsWorking() throws {
        let f = try ClaudeFixture(signedIn: A)
        try f.writeSession(A, s1, secondsAgo: 900, cliSessionId: "cli-long-turn")
        try f.writeTranscript("cli-long-turn", secondsAgo: 5)
        try f.writeSession(A, "22222222-2222-4222-8222-222222222222", secondsAgo: 900, cliSessionId: "cli-idle")
        try f.writeTranscript("cli-idle", secondsAgo: 900)

        #expect(f.switcher.workingSessions() == 1)
    }
}
