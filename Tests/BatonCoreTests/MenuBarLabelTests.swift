import Foundation
import Testing
@testable import BatonCore

/// docs/specs/menu-bar-usage/spec.md
@Suite("Usage in the menu bar")
struct MenuBarLabelTests {
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    let org = ClaudeFixture.org

    var accounts: [SavedAccount] {
        [ClaudeFixture.a, ClaudeFixture.b].enumerated().map { index, id in
            SavedAccount(accountId: id, orgId: org, email: nil, orgName: "Acme", savedAt: Double(index), addedAt: Double(index),
                         signIn: SignIn(config: [:], cookieSchema: 24, cookies: []))
        }
    }

    func label(_ entry: UsageEntry?, phase: Phase = .idle, current: String? = ClaudeFixture.a) -> MenuBarLabel {
        var usage: [String: UsageEntry] = [ClaudeFixture.b: UsageEntry(usage: Usage(session: .init(used: 5, resetsAt: nil),
                                                                                    week: .init(used: 5, resetsAt: nil)))]
        usage[ClaudeFixture.a] = entry
        return MenuBarLabel.make(accounts: accounts, current: current.map { Identity(account: $0, org: org) },
                                 usage: usage, phase: phase, now: now)
    }

    func entry(session: Double, sessionReset: TimeInterval? = nil, week: Double, weekReset: TimeInterval? = nil,
               failure: UsageFailure? = nil) -> UsageEntry {
        UsageEntry(usage: Usage(session: .init(used: session, resetsAt: sessionReset.map(now.addingTimeInterval)),
                                week: .init(used: week, resetsAt: weekReset.map(now.addingTimeInterval))),
                   failure: failure, checked: now)
    }

    // AC1, AC2: the signed-in account's meter and its Session percent, written as the panel writes it.
    @Test func showsTheSignedInAccountsMeterAndSessionPercent() {
        #expect(label(entry(session: 42, week: 18)) == .usage(MenuBarUsage(
            session: 0.42, week: 0.18, text: "42%", dimmed: false,
            accessibility: "Claude Desktop Baton: Session 42%, Week 18%",
            limits: [MenuBarLimit(label: "5H", percent: "42%"), MenuBarLimit(label: "WK", percent: "18%")])))
        guard case .usage(let low) = label(entry(session: 0.4, week: 3)) else { Issue.record("no usage"); return }
        #expect(low.text == "<1%")
    }

    // AC3: Session at 100% shows the time until the Session limit resets.
    @Test func reachedSessionLimitShowsTheTimeUntilItResets() {
        guard case .usage(let shown) = label(entry(session: 100, sessionReset: 72 * 60, week: 64, weekReset: 3 * 86_400))
        else { Issue.record("no usage"); return }
        #expect(shown.session == 1)
        #expect(shown.text == "↻ 1h 12m")
        #expect(shown.accessibility == "Claude Desktop Baton: limit reached, available again in 1h 12m")
    }

    // AC4: Week at 100% with Session below shows the Week reset, not the Session percent.
    @Test func reachedWeekLimitShowsTheWeekResetInsteadOfTheSessionPercent() {
        guard case .usage(let shown) = label(entry(session: 30, sessionReset: 3600, week: 100, weekReset: 2 * 86_400 + 3 * 3600))
        else { Issue.record("no usage"); return }
        #expect(shown.week == 1)
        #expect(shown.text == "↻ 2d 3h")
    }

    // AC5: with both limits reached, the later reset is when Claude can be used again.
    @Test func bothLimitsReachedShowTheLaterReset() {
        guard case .usage(let shown) = label(entry(session: 100, sessionReset: 72 * 60, week: 100, weekReset: 2 * 86_400 + 3 * 3600))
        else { Issue.record("no usage"); return }
        #expect(shown.text == "↻ 2d 3h")
    }

    // Assumption in the spec: a reached limit without a reset time shows 100%.
    @Test func reachedLimitWithoutAResetTimeShowsOneHundredPercent() {
        guard case .usage(let shown) = label(entry(session: 30, week: 100)) else { Issue.record("no usage"); return }
        #expect(shown.text == "100%")
    }

    // AC6: a switch or an add shows the spinner.
    @Test func switchingOrAddingShowsTheSpinner() {
        #expect(label(entry(session: 42, week: 18), phase: .switching(accountId: ClaudeFixture.b)) == .switching)
        #expect(label(entry(session: 42, week: 18), phase: .adding) == .switching)
    }

    // AC7: a failed refresh keeps the last values, dimmed.
    @Test func failedRefreshKeepsTheLastValuesDimmed() {
        #expect(label(entry(session: 42, week: 18, failure: .offline)) == .usage(MenuBarUsage(
            session: 0.42, week: 0.18, text: "42%", dimmed: true,
            accessibility: "Claude Desktop Baton: Session 42%, Week 18%, not current",
            limits: [MenuBarLimit(label: "5H", percent: "42%"), MenuBarLimit(label: "WK", percent: "18%")])))
    }

    // State 7: nothing received yet shows a dimmed empty meter and a dash.
    @Test func noUsageYetShowsADimmedEmptyMeter() {
        let empty = MenuBarUsage(session: 0, week: 0, text: "—", dimmed: true, accessibility: "Claude Desktop Baton: usage unavailable")
        #expect(label(nil) == .usage(empty))
        #expect(label(UsageEntry(failure: .signInAgain, lastAttempt: now)) == .usage(empty))
    }

    // AC8: no saved signed-in account means the baton alone.
    @Test func unsavedOrSignedOutShowsTheBaton() {
        #expect(label(entry(session: 42, week: 18), current: "eeeeeeee-0000-4000-8000-000000000005") == .icon)
        #expect(label(entry(session: 42, week: 18), current: nil) == .icon)
    }

    // MARK: layouts chosen in the "⋯" menu

    // Columns and stack read each limit's label, percent and time until it resets.
    @Test func eachLimitCarriesItsLabelPercentAndReset() {
        guard case .usage(let shown) = label(entry(session: 62, sessionReset: 72 * 60, week: 81, weekReset: 2 * 86_400 + 4 * 3600))
        else { Issue.record("no usage"); return }

        #expect(shown.limits == [MenuBarLimit(label: "5H", percent: "62%", reset: "1h 12m"),
                                 MenuBarLimit(label: "WK", percent: "81%", reset: "2d 4h")])
        #expect(shown.limits.map(\.columnText) == ["62%", "81%"])
    }

    // A column shows the time until a reached limit resets, as the bars layout's text does.
    @Test func aReachedLimitsColumnShowsTheTimeUntilItResets() {
        guard case .usage(let shown) = label(entry(session: 30, sessionReset: 3600, week: 100, weekReset: 2 * 86_400 + 3 * 3600)),
              case .usage(let unknown) = label(entry(session: 100, week: 40))
        else { Issue.record("no usage"); return }

        #expect(shown.limits.map(\.columnText) == ["30%", "↻ 2d 3h"])
        #expect(unknown.limits.map(\.columnText) == ["100%", "40%"])
    }

    @Test func aResetThatHasPassedIsNotShown() {
        guard case .usage(let shown) = label(entry(session: 12, sessionReset: -60, week: 40)) else { Issue.record("no usage"); return }

        #expect(shown.limits.map(\.reset) == [nil, nil])
    }

    // The "Icon" choice keeps the baton whatever the usage is; a switch still shows the spinner.
    @Test func theIconChoiceNeverShowsUsage() {
        let usage = [ClaudeFixture.a: entry(session: 42, week: 18)]
        let current = Identity(account: ClaudeFixture.a, org: org)

        #expect(MenuBarLabel.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now, content: .icon) == .icon)
        #expect(MenuBarLabel.make(accounts: accounts, current: current, usage: usage, phase: .adding, now: now, content: .icon) == .switching)
        guard case .usage = MenuBarLabel.make(accounts: accounts, current: current, usage: usage, phase: .idle, now: now,
                                               content: .iconAndUsage) else { Issue.record("no usage"); return }
    }

    @Test func theMenuBarChoiceIsKeptAndDefaultsToUsageInColumns() throws {
        let name = "baton-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(MenuBarStyle.load(defaults) == MenuBarStyle(content: .usage, layout: .columns))
        MenuBarStyle(content: .iconAndUsage, layout: .stack).save(defaults)
        #expect(MenuBarStyle.load(defaults) == MenuBarStyle(content: .iconAndUsage, layout: .stack))
        defaults.set("sideways", forKey: "menuBarLayout")
        #expect(MenuBarStyle.load(defaults).layout == .columns)
    }
}
