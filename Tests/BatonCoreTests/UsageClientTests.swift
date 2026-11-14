import Foundation
import Testing
@testable import BatonCore

/// Answers every request with a canned response and remembers the request.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var contentType = "application/json"
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var resetQueryStatus: Int?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let status = request.url?.query == nil ? Self.status : (Self.resetQueryStatus ?? Self.status)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Usage requests", .serialized)
struct UsageClientTests {
    let org = "0000000f-0000-4000-8000-00000000000f"
    let signIn = SignIn(config: [:], cookieSchema: 24, cookies: [
        ["host_key": .text(".claude.ai"), "name": .text("sessionKey"), "value": .text("sk"), "encrypted_value": .blob(Data())],
        ["host_key": .text(".claude.ai"), "name": .text("cf_clearance"), "value": .text("cf"), "encrypted_value": .blob(Data())],
    ])

    func client() -> UsageClient {
        StubProtocol.requests = []
        StubProtocol.resetQueryStatus = nil
        return UsageClient(protocolClasses: [StubProtocol.self], userAgent: "test", key: { Data(count: 16) })
    }

    // AC8
    @Test func usageIsAskedForTheAccountsOrganizationWithItsSessionCookie() async {
        let client = client()
        StubProtocol.status = 200
        StubProtocol.contentType = "application/json"
        StubProtocol.body = Data(#"{"five_hour":{"utilization":8},"seven_day":{"utilization":34}}"#.utf8)

        let result = await client.usage(orgId: org, signIn: signIn)

        #expect(result == .success(Usage(session: .init(used: 8, resetsAt: nil), week: .init(used: 34, resetsAt: nil))))
        #expect(StubProtocol.requests.first?.url?.absoluteString == "https://claude.ai/api/organizations/\(org)/usage")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk")
    }

    @Test func panelUsageRequestsReadOnlyResetInventoryWithTheSameSession() async throws {
        let client = client()
        StubProtocol.status = 200
        StubProtocol.contentType = "application/json"
        StubProtocol.body = Data(#"""
        {"five_hour":{"utilization":8},
         "cedar_ember":{"grants":[
           {"label":"One full limit reset","resets_left":1,"usable_now":true,"clears":["five_hour","seven_day"],"ends_at":"2026-12-10T22:00:00+00:00"},
           {"label":"One Fable reset","resets_left":1,"usable_now":true,"clears":["five_hour","seven_day_overage_included"]}
         ]}}
        """#.utf8)

        let usage = try await client.usage(orgId: org, signIn: signIn, includeLimitResets: true).get()

        #expect(usage.session?.used == 8)
        #expect(usage.limitResets?.map(\.name) == ["Full reset", "Fable reset"])
        #expect(usage.limitResets?.map(\.remaining) == [1, 1])
        #expect(usage.limitResets?.first?.expiresAt == Date(timeIntervalSince1970: 1_796_940_000))
        #expect(StubProtocol.requests.map(\.httpMethod) == ["GET"])
        #expect(StubProtocol.requests.first?.url?.absoluteString == "https://claude.ai/api/organizations/\(org)/usage?cedar_ember=1&skip_spend=1")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk")
    }

    @Test func rejectedResetQueryFallsBackToOrdinaryUsage() async throws {
        let client = client()
        StubProtocol.status = 200
        StubProtocol.resetQueryStatus = 400
        StubProtocol.contentType = "application/json"
        StubProtocol.body = Data(#"{"seven_day":{"utilization":34},"cedar_ember":null}"#.utf8)

        let usage = try await client.usage(orgId: org, signIn: signIn, includeLimitResets: true).get()

        #expect(usage.week?.used == 34)
        #expect(usage.limitResets == nil)
        #expect(StubProtocol.requests.count == 2)
        #expect(StubProtocol.requests.last?.url?.query == nil)
    }

    // AC8: a failed fetch carries the reason shown on hover.
    @Test func rejectedSessionAsksToSignInAgain() async {
        let client = client()
        StubProtocol.status = 401
        StubProtocol.contentType = "application/json"
        StubProtocol.body = Data(#"{"error":"unauthorized"}"#.utf8)

        #expect(await client.usage(orgId: org, signIn: signIn) == .failure(.signInAgain))
    }

    @Test func savedSignInWithoutASessionCookieIsNotSent() async {
        let client = client()
        let empty = SignIn(config: [:], cookieSchema: 24, cookies: [])

        #expect(await client.usage(orgId: org, signIn: empty) == .failure(.signInAgain))
        #expect(StubProtocol.requests.isEmpty)
    }

    // Account names: email and organization name come from claude.ai.
    @Test func accountInfoReadsEmailAndTheOrganizationsName() async {
        let client = client()
        StubProtocol.status = 200
        StubProtocol.contentType = "application/json"
        StubProtocol.body = Data(#"""
        {"email_address":"alex@example.com","memberships":[
          {"organization":{"uuid":"other","name":"Elsewhere"}},
          {"organization":{"uuid":"0000000f-0000-4000-8000-00000000000f","name":"Acme"}}]}
        """#.utf8)

        let info = await client.accountInfo(orgId: org, signIn: signIn)

        #expect(info.email == "alex@example.com")
        #expect(info.orgName == "Acme")
    }
}
