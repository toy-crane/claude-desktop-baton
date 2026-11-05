import Foundation
import Testing
@testable import BatonCore

@Suite("Saved accounts")
struct AccountStoreTests {

    private func legacyFile(_ id: String, savedAt: Double, email: String) -> Data {
        // The reference project's format: no addedAt, cookies as {i|r|s|b|n} values.
        Data(#"""
        {"accountId":"\#(id)","orgId":"0000000f-0000-4000-8000-00000000000f","email":"\#(email)","orgName":"Acme",
         "savedAt":\#(savedAt),"signIn":{"config":{"lastKnownAccountUuid":"\#(id)","oauth:tokenCacheV2":"enc"},
         "cookieSchema":24,"cookies":[{"host_key":{"s":".claude.ai"},"name":{"s":"sessionKey"},"encrypted_value":{"b":"djEwAAAA"},"expires_utc":{"i":"13400000000000000"}}]}}
        """#.utf8)
    }

    // AC14
    @Test func referenceAccountsAreImportedOnceWithoutChangingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baton-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let first = legacyFile(ClaudeFixture.b, savedAt: 1000, email: "sam@example.com")
        let second = legacyFile(ClaudeFixture.a, savedAt: 2000, email: "alex@example.com")
        try first.write(to: legacy.appendingPathComponent("\(ClaudeFixture.b).json"))
        try second.write(to: legacy.appendingPathComponent("\(ClaudeFixture.a).json"))
        let store = AccountStore(paths: AppPaths(root: root.appendingPathComponent("baton")))

        let imported = store.importLegacy(from: legacy)

        #expect(imported == 2)
        #expect(store.all().map(\.accountId) == [ClaudeFixture.b, ClaudeFixture.a])
        #expect(store.load(ClaudeFixture.a)?.signIn.cookies.first?["expires_utc"] == .integer("13400000000000000"))
        #expect(try Data(contentsOf: legacy.appendingPathComponent("\(ClaudeFixture.b).json")) == first)
        #expect(try Data(contentsOf: legacy.appendingPathComponent("\(ClaudeFixture.a).json")) == second)

        try store.remove(ClaudeFixture.b)
        #expect(store.importLegacy(from: legacy) == 0)
        #expect(store.load(ClaudeFixture.b) == nil)
    }

    @Test func withoutReferenceAccountsTheAppStartsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baton-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(paths: AppPaths(root: root))

        #expect(store.importLegacy(from: root.appendingPathComponent("missing")) == 0)
        #expect(store.all().isEmpty)
    }

    // Spec assumption: account names.
    @Test func namesUseTheOrganizationAndDisambiguateWithTheEmail() {
        func account(_ id: String, org: String?, email: String?) -> SavedAccount {
            SavedAccount(accountId: id, orgId: ClaudeFixture.org, email: email, orgName: org, savedAt: 0,
                         signIn: SignIn(config: [:], cookieSchema: 24, cookies: []))
        }
        let names = displayNames([
            account(ClaudeFixture.a, org: "Acme", email: "alex@example.com"),
            account(ClaudeFixture.b, org: "Acme", email: "sam@example.com"),
            account(ClaudeFixture.c, org: "riley@example.com's Organization", email: "riley@example.com"),
            account("dddddddd-0000-4000-8000-000000000004", org: "Northwind Labs", email: "s@northwind.com"),
        ])

        #expect(names[ClaudeFixture.a] == "Acme · alex")
        #expect(names[ClaudeFixture.b] == "Acme · sam")
        #expect(names[ClaudeFixture.c] == "Personal")
        #expect(names["dddddddd-0000-4000-8000-000000000004"] == "Northwind Labs")
    }
}
