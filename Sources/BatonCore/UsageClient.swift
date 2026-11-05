import Foundation
import Security

/// Talks to claude.ai with an account's own session cookies. Redirects are refused and nothing is stored.
public final class UsageClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    private let userAgent: String
    private let keySource: @Sendable () throws -> Data
    private let lock = NSLock()
    private var cachedKey: Data?

    public init(protocolClasses: [AnyClass]? = nil, userAgent: String, key: @escaping @Sendable () throws -> Data) {
        self.userAgent = userAgent
        self.keySource = key
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? { nil }

    /// The cookie key is read from the Keychain once; reading it may show a macOS prompt.
    private func cookieKey() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        let key = try keySource()
        cachedKey = key
        return key
    }

    private func get(_ path: String, signIn: SignIn) async -> Result<Data, UsageFailure> {
        let key: Data
        do { key = try cookieKey() } catch {
            return .failure(error as? UsageFailure ?? .keychain(error.localizedDescription))
        }
        guard let cookie = CookieCrypto.header(signIn, key: key) else { return .failure(.signInAgain) }
        var request = URLRequest(url: URL(string: "https://claude.ai\(path)")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let isJSON = http?.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true
            switch http?.statusCode {
            case 200: return .success(data)
            case 401, 403 where isJSON: return .failure(.signInAgain)
            case 403: return .failure(.blocked)
            default: return .failure(.http(http?.statusCode ?? 0))
            }
        } catch {
            return .failure(.offline)
        }
    }

    public func usage(orgId: String, signIn: SignIn) async -> Result<Usage, UsageFailure> {
        await get("/api/organizations/\(orgId)/usage", signIn: signIn).flatMap { data in
            (try? Usage(json: data)).map(Result.success) ?? .failure(.unexpected)
        }
    }

    /// Email and organization name, for account names.
    public func accountInfo(orgId: String, signIn: SignIn) async -> (email: String?, orgName: String?) {
        guard case .success(let data) = await get("/api/account", signIn: signIn),
              let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (nil, nil) }
        let email = body["email_address"] as? String ?? body["email"] as? String
        let orgs = (body["memberships"] as? [[String: Any]] ?? []).compactMap { $0["organization"] as? [String: Any] }
        return (email, orgs.first { $0["uuid"] as? String == orgId }?["name"] as? String)
    }
}

/// Reads Claude's cookie key from the login Keychain item "Claude Safe Storage".
/// macOS asks the user once; "Always Allow" stops repeat prompts for a stably signed app.
public enum ClaudeKeychain {
    public static func cookieKey() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Claude Safe Storage",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let password = item as? Data else { throw UsageFailure.keychain("Claude's Safe Storage key is missing.") }
            return CookieCrypto.key(password: password)
        case errSecItemNotFound:
            throw UsageFailure.keychain("Claude's Safe Storage key is not in the Keychain. Open Claude once and sign in.")
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw UsageFailure.keychain("Keychain access to Claude Safe Storage was not allowed, so usage cannot be checked.")
        default:
            throw UsageFailure.keychain("The Keychain could not be read (\(status)).")
        }
    }

    /// Claude Desktop's own user agent, so requests look like the app's.
    public static func userAgent(claudeApp: URL) -> String {
        let claude = Bundle(url: claudeApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let electron = Bundle(url: claudeApp.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"))?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Claude/\(claude) Electron/\(electron) Safari/537.36"
    }
}
