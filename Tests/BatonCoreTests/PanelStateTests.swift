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

        #expect(rows.map(\.name) == ["Acme · alex", "Acme · jordan", "Acme · sam"])
        #expect(rows.map(\.isCurrent) == [true, false, false])
        #expect(rows[0].session == Meter(fraction: 0.62, text: "62%", atLimit: false, reset: "1h"))
        #expect(rows[0].week == Meter(fraction: 0.81, text: "81%", atLimit: false,
                                      reset: UsageText.resetLabel(now.addingTimeInterval(86_400), from: now)))
    }

    func modelEntry(failure: UsageFailure? = nil) -> [String: UsageEntry] {
        let reset = now.addingTimeInterval(86_400)
        let limits = [Usage.ModelLimit(name: "Fable", bucket: .init(used: 24, resetsAt: reset), allowancePercent: 50),
                      Usage.ModelLimit(name: "Orion", bucket: .init(used: 100, resetsAt: reset))]
        var entries = usage
        entries[ClaudeFixture.a] = UsageEntry(usage: Usage(session: .init(used: 62, resetsAt: nil), week: .init(used: 81, resetsAt: nil),
                                                           models: limits), failure: failure, checked: now)
        return entries
    }

    // Model weekly limits: a meter per limit under Week, red only when reached; accounts without one are unchanged.
    @Test func modelLimitsShowAsMetersAfterWeek() {
        let rows = state(usage: modelEntry()).rows

        #expect(rows[0].models.map(\.name) == ["Fable", "Orion"])
        #expect(rows[0].models[0].meter.fraction == 0.24 && rows[0].models[0].meter.text == "24%")
        #expect(!rows[0].models[0].meter.atLimit && rows[0].models[1].meter.atLimit)
        #expect(rows[1].models.isEmpty && rows[2].models.isEmpty)
        #expect(rows[1] == state().rows[1])
    }

    // Hover adds each model limit's reset and allowance; without an allowance only the reset.
    @Test func hoverShowsModelLimitResetAndAllowance() {
        let tooltip = state(usage: modelEntry()).rows[0].tooltip
        let reset = Date(timeIntervalSince1970: 1_793_000_000 + 86_400).formatted(date: .abbreviated, time: .shortened)

        #expect(tooltip.contains("Fable resets \(reset) · up to 50% of Week"))
        #expect(tooltip.contains("Orion resets \(reset)\n") || tooltip.hasSuffix("Orion resets \(reset)"))
    }

    // A failed refresh keeps a model meter the account had, reading "—" with an empty bar.
    @Test func failedRefreshBlanksModelMeters() {
        let meter = state(usage: modelEntry(failure: .offline)).rows[0].models[0]

        #expect(meter.name == "Fable")
        #expect(meter.meter == Meter(fraction: 0, text: "—", atLimit: false))
    }

    // AC8: a reached limit turns red and shows when it resets.
    @Test func reachedLimitIsMarkedWithTheTimeUntilItResets() {
        let row = state().rows[1]

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
        #expect(rows[0].week.reset == UsageText.resetLabel(now.addingTimeInterval(2 * 86_400 + 4 * 3600), from: now))
        #expect(rows[2].session.reset == nil)
        #expect(rows[2].week.reset == nil)
    }

    // AC8: a failed fetch shows dashes, empty bars and the reason on hover.
    @Test func failedFetchShowsDashesAndTheReason() {
        var entries = usage
        entries[ClaudeFixture.b] = UsageEntry(failure: .offline, lastAttempt: now)

        let row = state(usage: entries).rows[2]

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

    // User's choice (option C): the signed-in account sits apart, with its email; the rest are in name order.
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
        #expect(s.rows.map(\.isTarget) == [false, false, true])
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

    // MARK: switch-to order (docs/specs/switch-to-order)

    func named(_ names: [(String, String)], usage: [String: UsageEntry] = [:], current: String? = nil) -> PanelState {
        let accounts = names.map { id, name in
            SavedAccount(accountId: id, orgId: org, email: nil, orgName: name, savedAt: 1, addedAt: 1,
                         signIn: SignIn(config: [:], cookieSchema: 24, cookies: []))
        }
        return PanelState.make(accounts: accounts, current: current.map { Identity(account: $0, org: org) },
                               usage: usage, phase: .idle, now: now)
    }

    func id(_ n: Int) -> String { String(format: "dddddddd-0000-4000-8000-%012d", n) }

    func weekEntry(session: Double = 10, week: Double, weekReset: TimeInterval? = 86_400, models: [Usage.ModelLimit] = []) -> UsageEntry {
        UsageEntry(usage: Usage(session: .init(used: session, resetsAt: now.addingTimeInterval(3600)),
                                week: .init(used: week, resetsAt: weekReset.map(now.addingTimeInterval)), models: models), checked: now)
    }

    // AC1, AC1a: case-insensitive, numbers by value.
    @Test func switchToIsInNameOrderWithNumbersByValue() {
        let plain = named([(id(1), "Studio"), (id(2), "Acme"), (id(3), "personal")])
        #expect(plain.switchTo.map(\.name) == ["Acme", "personal", "Studio"])

        let numbered = named([(id(1), "toycrane 2"), (id(2), "toycrane 10"), (id(3), "toycrane"), (id(4), "toycrane 1")])
        #expect(numbered.switchTo.map(\.name) == ["toycrane", "toycrane 1", "toycrane 2", "toycrane 10"])
    }

    // AC2, AC3: Week at 100% before its reset goes to the bottom group, in name order, with its reset.
    @Test func weekAtLimitMovesToTheBottomGroupInNameOrder() {
        let s = named([(id(1), "Zed"), (id(2), "Beta"), (id(3), "Alpha")],
                      usage: [id(1): weekEntry(week: 100), id(2): weekEntry(week: 100), id(3): weekEntry(week: 20)])

        #expect(s.switchTo.map(\.name) == ["Alpha"])
        #expect(s.weekLimitReached.map(\.name) == ["Beta", "Zed"])
        #expect(s.weekLimitReached[0].week.reset == UsageText.resetLabel(now.addingTimeInterval(86_400), from: now))
    }

    // AC4, AC5, AC6: only Week counts.
    @Test func sessionModelAndUnknownUsageStayInTheMainList() {
        let fable = [Usage.ModelLimit(name: "Fable", bucket: .init(used: 100, resetsAt: now.addingTimeInterval(86_400)))]
        let s = named([(id(1), "Session"), (id(2), "Model"), (id(3), "Failed"), (id(4), "Never")],
                      usage: [id(1): weekEntry(session: 100, week: 62), id(2): weekEntry(week: 40, models: fable),
                              id(3): UsageEntry(usage: Usage(session: nil, week: .init(used: 100, resetsAt: now.addingTimeInterval(86_400))),
                                                failure: .offline, lastAttempt: now)])

        #expect(s.weekLimitReached.isEmpty)
        #expect(s.switchTo.count == 4)
        #expect(s.rows.first { $0.name == "Session" }?.session.atLimit == true)
        #expect(s.rows.first { $0.name == "Failed" }?.week.text == "—")
    }

    // AC7 and AC9: no group without an out-of-Week account; a passed (or unknown) reset puts it back at once.
    @Test func resetTimePassedOrUnknownKeepsTheAccountInTheMainList() {
        let passed = named([(id(1), "A")], usage: [id(1): weekEntry(week: 100, weekReset: -1)])
        #expect(passed.weekLimitReached.isEmpty && passed.switchTo.count == 1)

        let unknown = named([(id(1), "A")], usage: [id(1): weekEntry(week: 100, weekReset: nil)])
        #expect(unknown.weekLimitReached.isEmpty)

        // The same data a minute before the reset is out of Week.
        let before = named([(id(1), "A")], usage: [id(1): weekEntry(week: 100, weekReset: 60)])
        #expect(before.weekLimitReached.count == 1 && before.switchTo.isEmpty)
    }

    // AC10: the signed-in account stays under "Signed in" even at Week 100%.
    @Test func signedInAccountStaysUpTopAtWeekLimit() {
        let s = named([(id(1), "A"), (id(2), "B")], usage: [id(1): weekEntry(week: 100), id(2): weekEntry(week: 100)], current: id(1))

        #expect(s.signedIn?.name == "A")
        #expect(s.switchTo.isEmpty)
        #expect(s.weekLimitReached.map(\.name) == ["B"])
    }

    // AC11: the "Remove account ›" menu reads state.rows, which is in name order.
    @Test func rowsAreInNameOrderForTheRemoveMenu() {
        let s = named([(id(1), "b 10"), (id(2), "b 9"), (id(3), "A")], usage: [id(1): weekEntry(week: 100)])

        #expect(s.rows.map(\.name) == ["A", "b 9", "b 10"])
    }
}
