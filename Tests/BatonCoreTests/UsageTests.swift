import Foundation
import Testing
@testable import BatonCore

private func hex(_ text: String) -> Data {
    var data = Data()
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        data.append(UInt8(text[index..<next], radix: 16)!)
        index = next
    }
    return data
}

@Suite("Usage")
struct UsageTests {
    // Worked example produced outside this code: Python's hashlib.pbkdf2_hmac for the key and
    // `openssl enc -aes-128-cbc` (IV of 16 spaces) over SHA-256(".claude.ai") + "sk-ant-test-value".
    static let password = Data("peanuts-test".utf8)
    static let expectedKey = hex("64f5220b352c3e5f29c97a2147cbb67a")
    static let ciphertext = Data("v10".utf8) + hex("844d66ee984d6fe12a053cae151770c910f2240bf5d735f13a49a7f0facebb3db0e6474c4525fdbf15a0dc326e7f68e2f172a2ab3100afe595520836d0919bc4")

    // AC8: usage is read from each account's own encrypted session cookie.
    @Test func derivesChromiumCookieKeyFromTheKeychainPassword() {
        #expect(CookieCrypto.key(password: Self.password) == Self.expectedKey)
    }

    // AC8
    @Test func decryptsAChromiumV10CookieWithItsHostPrefix() {
        #expect(CookieCrypto.decrypt(Self.ciphertext, key: Self.expectedKey, host: ".claude.ai", schema: 24) == "sk-ant-test-value")
    }

    // Safety: a value whose host prefix does not match is not trusted.
    @Test func rejectsACookieWhoseHostPrefixDoesNotMatch() {
        #expect(CookieCrypto.decrypt(Self.ciphertext, key: Self.expectedKey, host: "evil.example", schema: 24) == nil)
    }

    // Safety: only session cookies leave the machine, never browser or analytics cookies.
    @Test func cookieHeaderCarriesOnlySessionCookies() {
        func row(_ name: String, _ value: String) -> CookieRow {
            ["host_key": .text(".claude.ai"), "name": .text(name), "value": .text(value), "encrypted_value": .blob(Data())]
        }
        let signIn = SignIn(config: [:], cookieSchema: 24,
                            cookies: [row("sessionKey", "sk"), row("lastActiveOrg", "org"), row("cf_clearance", "cf"), row("ajs_user_id", "u")])

        let header = CookieCrypto.header(signIn, key: Self.expectedKey)

        #expect(header == "sessionKey=sk; lastActiveOrg=org")
    }

    // AC8
    @Test func readsSessionAndWeeklyPercentUsedWithResetTimes() throws {
        let json = Data(#"""
        {"five_hour":{"utilization":62.0,"resets_at":"2026-11-05T06:40:00.123456+00:00"},
         "seven_day":{"utilization":81,"resets_at":"2026-11-09T00:00:00+00:00"},
         "seven_day_opus":null}
        """#.utf8)

        let usage = try Usage(json: json)

        #expect(usage.session?.used == 62)
        #expect(usage.week?.used == 81)
        #expect(usage.session?.resetsAt == Date(timeIntervalSince1970: 1_793_860_800))
    }

    // AC8: a reached limit shows how long until it resets.
    @Test func resetCountdownReadsInHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UsageText.until(now.addingTimeInterval(72 * 60), from: now) == "1h 12m")
        #expect(UsageText.until(now.addingTimeInterval(12 * 60 + 30), from: now) == "13m")
        #expect(UsageText.until(now.addingTimeInterval(50 * 3600), from: now) == "2d 2h")
        #expect(UsageText.until(now.addingTimeInterval(-5), from: now) == "now")
    }

    @Test func percentagesReadLikeClaudesOwnUsageScreen() {
        #expect(UsageText.percent(0) == "0%")
        #expect(UsageText.percent(61.6) == "62%")
        #expect(UsageText.percent(0.4) == "<1%")
        #expect(UsageText.percent(100) == "100%")
    }

    // AC8: every 2 minutes, and on opening the panel when older than 1 minute.
    @Test func usageRefreshesEveryTwoMinutesOrOnOpeningWhenOlderThanOne() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UsageSchedule.isDue(lastAttempt: nil, now: now, panelOpening: false))
        #expect(!UsageSchedule.isDue(lastAttempt: now.addingTimeInterval(-90), now: now, panelOpening: false))
        #expect(UsageSchedule.isDue(lastAttempt: now.addingTimeInterval(-121), now: now, panelOpening: false))
        #expect(UsageSchedule.isDue(lastAttempt: now.addingTimeInterval(-61), now: now, panelOpening: true))
        #expect(!UsageSchedule.isDue(lastAttempt: now.addingTimeInterval(-30), now: now, panelOpening: true))
    }
}
