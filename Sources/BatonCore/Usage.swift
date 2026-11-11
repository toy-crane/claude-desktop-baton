import CommonCrypto
import Foundation

/// claude.ai's usage response for one organization.
public struct Usage: Equatable, Sendable, Codable {
    public struct Bucket: Equatable, Sendable, Codable {
        /// Percent used, 0–100.
        public let used: Double
        public let resetsAt: Date?
        public init(used: Double, resetsAt: Date?) { self.used = used; self.resetsAt = resetsAt }
        public var isAtLimit: Bool { used >= 100 }
    }
    /// The current-session (5-hour) limit.
    public let session: Bucket?
    public let week: Bucket?
    /// Weekly limits that apply to one model, in the order claude.ai lists them; empty when the plan has none.
    public let models: [ModelLimit]

    /// A weekly limit for one model, such as "Fable".
    public struct ModelLimit: Equatable, Sendable, Codable {
        public let name: String
        public let bucket: Bucket
        /// The share of the weekly limit this model may use, in percent ("up to 50%"); nil when not reported.
        public let allowancePercent: Double?
        public init(name: String, bucket: Bucket, allowancePercent: Double? = nil) {
            self.name = name; self.bucket = bucket; self.allowancePercent = allowancePercent
        }
    }

    public init(session: Bucket?, week: Bucket?, models: [ModelLimit] = []) {
        self.session = session; self.week = week; self.models = models
    }

    // Saved usage from before model limits existed has no `models`; it decodes as none.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        session = try values.decodeIfPresent(Bucket.self, forKey: .session)
        week = try values.decodeIfPresent(Bucket.self, forKey: .week)
        models = try values.decodeIfPresent([ModelLimit].self, forKey: .models) ?? []
    }

    public init(json: Data) throws {
        guard let body = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            throw UsageFailure.unexpected
        }
        session = Self.bucket(body["five_hour"])
        week = Self.bucket(body["seven_day"])
        models = Self.modelLimits(body)
    }

    /// `weekly_scoped` entries of `limits` that name a model. Anything unexpected here yields fewer or no
    /// model limits and never affects Session or Week.
    static func modelLimits(_ body: [String: Any]) -> [ModelLimit] {
        guard let limits = body["limits"] as? [Any] else { return [] }
        let shares = body["weekly_scoped_shares"] as? [Any] ?? []
        return limits.enumerated().compactMap { index, value in
            guard let limit = value as? [String: Any], limit["kind"] as? String == "weekly_scoped",
                  let scope = limit["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                  let name = (model["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let bucket = bucket(["utilization": limit["percent"] as Any, "resets_at": limit["resets_at"] as Any])
            else { return nil }
            let allowance = shares.lazy.compactMap { $0 as? [String: Any] }
                .first { ($0["limit_index"] as? NSNumber)?.intValue == index }
                .flatMap { $0["allowance_percent_of_weekly"] as? NSNumber }
                .flatMap { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite ? min(100, max(0, $0.doubleValue)) : nil }
            return ModelLimit(name: name, bucket: bucket, allowancePercent: allowance)
        }
    }

    static func bucket(_ value: Any?) -> Bucket? {
        guard let object = value as? [String: Any], let number = object["utilization"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return Bucket(used: min(100, max(0, number.doubleValue)), resetsAt: (object["resets_at"] as? String).flatMap(date))
    }

    /// resets_at can carry fractional seconds, which ISO8601DateFormatter does not accept by default.
    static func date(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

public enum UsageText {
    /// Percent used, as Claude shows it.
    public static func percent(_ used: Double) -> String {
        if used <= 0 { return "0%" }
        if used >= 100 { return "100%" }
        if used < 1 { return "<1%" }
        return "\(Int(used.rounded()))%"
    }

    /// When a reset happens, for the panel: the time until it within a day ("1h 12m"), otherwise the
    /// weekday and time ("Thu 11:00 AM"), which is easier to read for a reset days away.
    public static func resetLabel(_ date: Date, from now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard date.timeIntervalSince(now) >= 24 * 60 * 60 else { return until(date, from: now) }
        return date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).hour().minute())
    }

    /// Time until a reset: "1h 12m", "13m", "2d 2h".
    public static func until(_ date: Date, from now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        let days = minutes / 1440, hours = minutes % 1440 / 60, rest = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h" }
        return "\(rest)m"
    }
}

public enum UsageSchedule {
    public static let interval: TimeInterval = 120
    public static let onOpen: TimeInterval = 60

    /// Usage refreshes every 2 minutes, and when the panel opens if it is older than 1 minute.
    public static func isDue(lastAttempt: Date?, now: Date, panelOpening: Bool) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= (panelOpening ? onOpen : interval)
    }
}

public enum CookieCrypto {
    /// Chromium's macOS cookie key: the Keychain password stretched with PBKDF2-SHA1.
    public static func key(password: Data) -> Data {
        var key = Data(count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     passwordBytes.bindMemory(to: Int8.self).baseAddress, password.count,
                                     salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                     keyBytes.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128)
            }
        }
        return status == kCCSuccess ? key : Data()
    }

    static func sha256(_ data: Data) -> Data {
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), out.bindMemory(to: UInt8.self).baseAddress) }
        }
        return digest
    }

    /// AES-128-CBC with an IV of 16 spaces after a "v10" prefix. From cookie database
    /// version 24 the plaintext starts with the SHA-256 of the cookie's host.
    public static func decrypt(_ encrypted: Data, key: Data, host: String, schema: Int) -> String? {
        guard encrypted.count > 3, encrypted.prefix(3) == Data("v10".utf8), key.count == kCCKeySizeAES128 else { return nil }
        let body = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var out = Data(count: body.count + kCCBlockSizeAES128)
        var written = 0
        let capacity = out.count
        let status = out.withUnsafeMutableBytes { outBytes in
            body.withUnsafeBytes { bodyBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                bodyBytes.baseAddress, body.count, outBytes.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        var plain = out.prefix(written)
        if schema >= 24 {
            guard plain.count >= 32, plain.prefix(32) == sha256(Data(host.utf8)) else { return nil }
            plain = plain.dropFirst(32)
        }
        return String(data: plain, encoding: .utf8)
    }

    static let sessionCookies: Set<String> = ["sessionKey", "sessionKeyV3", "sessionKeyLC", "sessionKeyV3LC",
                                              "lastActiveOrg", "routingHint", "anthropic-device-id"]

    /// Only the session cookies the usage request needs; browser and analytics cookies stay out.
    public static func header(_ signIn: SignIn, key: Data) -> String? {
        var parts: [String] = []
        var hasSession = false
        for row in signIn.cookies {
            guard let name = row["name"]?.text, sessionCookies.contains(name), let host = row["host_key"]?.text else { continue }
            let value: String?
            if let encrypted = row["encrypted_value"]?.blob, !encrypted.isEmpty {
                value = decrypt(encrypted, key: key, host: host, schema: signIn.cookieSchema)
            } else {
                value = row["value"]?.text
            }
            guard let value, !value.isEmpty else { continue }
            if name == "sessionKey" { hasSession = true }
            parts.append("\(name)=\(value)")
        }
        return hasSession ? parts.joined(separator: "; ") : nil
    }
}

public enum UsageFailure: Error, Equatable, Sendable {
    case signInAgain, blocked, http(Int), offline, unexpected, keychain(String)

    /// Shown on hover beside the account name.
    public var reason: String {
        switch self {
        case .signInAgain: return "The saved sign-in no longer works. Sign in to this account in Claude again."
        case .blocked: return "claude.ai refused the request."
        case .http(let status): return "claude.ai did not return usage (HTTP \(status))."
        case .offline: return "claude.ai didn't respond."
        case .unexpected: return "claude.ai returned usage in an unexpected format."
        case .keychain(let text): return text
        }
    }
}
