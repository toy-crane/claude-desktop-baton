import Foundation
import Testing
@testable import BatonCore

@Suite("Menu bar panel")
struct PanelStateTests {
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    let org = ClaudeFixture.org

    func account(_ id: String, email: String, added: Double) -> SavedAccount {
        SavedAccount(accountId: id, orgId: org, email: email, orgName: "Acme", savedAt: added, addedAt: added,
                     signIn: SignIn(config: [:], cookieSchema: 24, cookies: []))
    }

    var accounts: [SavedAccount] {
        [account(ClaudeFixture.a, email: "alex@example.com", added: 1),
         account(ClaudeFixture.b, email: "sam@example.com", added: 2),
         account(ClaudeFixture.c, email: "jordan@example.com", added: 3)]
    }

    var usage: [String: UsageEntry] {
        [ClaudeFixture.a: UsageEntry(usage: Usage(session: .init(used: 62, resetsAt: now.addingTimeInterval(3600)),
                                                  week: .init(used: 81, resetsAt: now.addingTimeInterval(86_400))),
                                     lastAttempt: now.addingTimeInterval(-60), checked: now.addingTimeInterval(-60)),
         ClaudeFixture.b: UsageEntry(usage: Usage(session: .init(used: 8, resetsAt: nil), week: .init(used: 34, resetsAt: nil)),
                                     checked: now.addingTimeInterval(-60)),
         ClaudeFixture.c: UsageEntry(usage: Usage(session: .init(used: 100, resetsAt: now.addingTimeInterval(72 * 60)),
                                                  week: .init(used: 97, resetsAt: nil)),
                                     checked: now.addingTimeInterval(-60))]
    }

    func state(_ phase: Phase = .idle, usage: [String: UsageEntry]? = nil) -> PanelState {
        PanelState.make(accounts: accounts, current: Identity(account: ClaudeFixture.a, org: org),
                        usage: usage ?? self.usage, phase: phase, now: now)
    }

    // AC8 and panel layout: one block per account with Session and Week percent, current marked.
    @Test func eachAccountShowsSessionAndWeekPercentWithTheCurrentOneMarked() {
        let rows = state().rows

        #expect(rows.map(\.name) == ["Acme · alex", "Acme · sam", "Acme · jordan"])
        #expect(rows.map(\.isCurrent) == [true, false, false])
        #expect(rows[0].session == Meter(fraction: 0.62, text: "62%", atLimit: false, reset: "1h"))
        #expect(rows[0].week == Meter(fraction: 0.81, text: "81%", atLimit: false, reset: "1d"))
    }

    // AC8: a reached limit turns red and shows when it resets.
    @Test func reachedLimitIsMarkedWithTheTimeUntilItResets() {
        let row = state().rows[2]

        #expect(row.session.atLimit)
        #expect(!row.week.atLimit)
        #expect(row.session.reset == "1h 12m")
    }

    // Each limit carries the time until it resets, shown beside its bar; an unknown or past reset shows nothing.
    @Test func eachLimitShowsTheTimeUntilItResets() {
        var entries = usage
        entries[ClaudeFixture.a] = UsageEntry(usage: Usage(session: .init(used: 10, resetsAt: now.addingTimeInterval(-60)),
                                                           week: .init(used: 81, resetsAt: now.addingTimeInterval(2 * 86_400 + 4 * 3600))))

        let rows = state(usage: entries).rows

        #expect(rows[0].session.reset == nil)
        #expect(rows[0].week.reset == "2d 4h")
        #expect(rows[1].session.reset == nil)
        #expect(rows[1].week.reset == nil)
    }

    // AC8: a failed fetch shows dashes, empty bars and the reason on hover.
    @Test func failedFetchShowsDashesAndTheReason() {
        var entries = usage
        entries[ClaudeFixture.b] = UsageEntry(failure: .offline, lastAttempt: now)

        let row = state(usage: entries).rows[1]

        #expect(row.session == Meter(fraction: 0, text: "—", atLimit: false))
        #expect(row.week.text == "—")
        #expect(row.failureReason == "claude.ai didn't respond.")
    }

    // AC6
    @Test func selectingAnotherAccountAsksFirstOnlyWhenSessionsAreWorking() {
        let current = Identity(account: ClaudeFixture.a, org: org)
        #expect(SwitchDecision.onSelect(ClaudeFixture.b, current: current, working: 2) == .confirm(working: 2))
        #expect(SwitchDecision.onSelect(ClaudeFixture.b, current: current, working: 0) == .start)
        #expect(SwitchDecision.onSelect(ClaudeFixture.a, current: current, working: 3) == .none)
    }

    // User's choice (option C): the signed-in account sits apart, with its email; the rest keep their saved order.
    @Test func signedInAccountIsSeparatedFromTheAccountsToSwitchTo() {
        let s = PanelState.make(accounts: accounts, current: Identity(account: ClaudeFixture.b, org: org),
                                usage: usage, phase: .idle, now: now)

        #expect(s.signedIn?.name == "Acme · sam")
        #expect(s.signedIn?.email == "sam@example.com")
        #expect(s.switchTo.map(\.name) == ["Acme · alex", "Acme · jordan"])
    }

    @Test func unsavedSignedInAccountLeavesEverySavedAccountUnderSwitchTo() {
        let s = PanelState.make(accounts: accounts, current: Identity(account: "eeeeeeee-0000-4000-8000-000000000005", org: org),
                                usage: usage, phase: .idle, now: now)

        #expect(s.signedIn == nil)
        #expect(s.switchTo.count == 3)
    }

    // Panel while switching (user's change: no switching messages inside the panel):
    // the target is marked and everything is disabled.
    @Test func switchingMarksTheTargetAndDisablesTheRest() {
        let s = state(.switching(accountId: ClaudeFixture.b))

        #expect(s.busy)
        #expect(s.rows.map(\.isTarget) == [false, true, false])
        #expect(s.rows.map(\.isDisabled) == [true, true, true])
    }

    // AC6 (user's change: as an alert): the confirmation names the account and the working sessions.
    @Test func confirmationAlertNamesTheAccountAndWorkingSessions() {
        let alert = Alerts.confirmSwitch(to: "Acme · sam", working: 2)

        #expect(alert.title == "Switch to Acme · sam?")
        #expect(alert.message.hasPrefix("2 sessions are working in Claude."))
        #expect(alert.buttons == ["Switch", "Cancel"])
        #expect(Alerts.confirmSwitch(to: "X", working: 1).message.hasPrefix("1 session is working in Claude."))
    }

    // AC7 (user's change: as an alert): a failed switch offers to put the previous account back.
    @Test func failureAlertOffersToPutThePreviousAccountBack() {
        let alert = Alerts.switchFailed(to: "Acme · jordan", message: "The saved sign-in may have expired.", putBack: "Acme · alex")

        #expect(alert.title == "Couldn't switch to Acme · jordan")
        #expect(alert.message == "The saved sign-in may have expired.")
        #expect(alert.buttons == ["Put Back Acme · alex", "OK"])
        #expect(Alerts.switchFailed(to: "X", message: "m", putBack: nil).buttons == ["OK"])
    }

    // AC12 (user's change: as an alert): a skipped sync is reported after the switch.
    @Test func syncWarningAlertSaysTheSwitchWorkedButSessionsWereNotSynced() {
        let alert = Alerts.syncSkipped(to: "Acme · sam", reason: "only 0 of 2 session files look familiar")

        #expect(alert.title == "Switched to Acme · sam")
        #expect(alert.message.contains("only 0 of 2 session files look familiar"))
        #expect(alert.buttons == ["OK"])
    }

    // "⋯" menu: the time of the last refresh.
    @Test func lastRefreshTimeReadsInMinutes() {
        #expect(state().updated == "updated 1 min ago")
    }
}
