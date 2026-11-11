import Foundation

public struct SavedAccount: Codable, Equatable, Sendable, Identifiable {
    public let accountId: String
    public let orgId: String
    public var email: String?
    public var orgName: String?
    /// Milliseconds since 1970; changes whenever the sign-in is saved again.
    public var savedAt: Double
    /// When the account was first saved; sets its place in the list. Missing in imported files.
    public var addedAt: Double?
    public var signIn: SignIn

    public var id: String { accountId }
    public var identity: Identity { Identity(account: accountId, org: orgId) }

    public init(accountId: String, orgId: String, email: String? = nil, orgName: String? = nil,
                savedAt: Double, addedAt: Double? = nil, signIn: SignIn) {
        self.accountId = accountId
        self.orgId = orgId
        self.email = email
        self.orgName = orgName
        self.savedAt = savedAt
        self.addedAt = addedAt
        self.signIn = signIn
    }
}

/// One private file per account. The sign-in inside stays encrypted with Claude's own key.
public final class AccountStore: @unchecked Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    func file(_ accountId: String) -> URL { paths.accountsDir.appendingPathComponent("\(accountId).json") }

    public func save(_ account: SavedAccount) throws {
        guard SessionSync.match(SessionSync.uuidName, account.accountId) != nil else { throw BatonError("That account id is not valid.") }
        var account = account
        account.addedAt = account.addedAt ?? load(account.accountId)?.addedAt ?? account.savedAt
        try writePrivate(JSONEncoder().encode(account), to: file(account.accountId))
    }

    public func load(_ accountId: String) -> SavedAccount? {
        guard SessionSync.match(SessionSync.uuidName, accountId) != nil,
              let data = try? Data(contentsOf: file(accountId)) else { return nil }
        return try? JSONDecoder().decode(SavedAccount.self, from: data)
    }

    /// Saved accounts in the order they were first saved.
    public func all() -> [SavedAccount] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.accountsDir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { load(String($0.dropLast(5))) }
            .sorted { ($0.addedAt ?? $0.savedAt, $0.accountId) < ($1.addedAt ?? $1.savedAt, $1.accountId) }
    }

    public func remove(_ accountId: String) throws {
        guard SessionSync.match(SessionSync.uuidName, accountId) != nil else { return }
        try? FileManager.default.removeItem(at: file(accountId))
    }

    /// Copies accounts saved by the reference project, once, without changing its files.
    /// Returns how many were imported.
    @discardableResult
    public func importLegacy(from folder: URL) -> Int {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: paths.accountsDir.path),
              let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return 0 }
        var imported = 0
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                  var account = try? JSONDecoder().decode(SavedAccount.self, from: data) else { continue }
            account.addedAt = account.addedAt ?? account.savedAt
            if (try? save(account)) != nil { imported += 1 }
        }
        if imported == 0 { try? fm.createDirectory(at: paths.accountsDir, withIntermediateDirectories: true) }
        return imported
    }
}

/// The name shown for each account: its organization, "Personal" for Claude's default
/// personal organization, and the email's local part appended when two names would match.
public func displayNames(_ accounts: [SavedAccount]) -> [String: String] {
    func base(_ a: SavedAccount) -> String {
        if let org = a.orgName, !org.isEmpty {
            return org.hasSuffix("'s Organization") || org.hasSuffix("’s Organization") ? "Personal" : org
        }
        return a.email.map(localPart) ?? "Account \(a.accountId.prefix(8))"
    }
    func localPart(_ email: String) -> String { String(email.split(separator: "@").first ?? Substring(email)) }
    let bases = Dictionary(uniqueKeysWithValues: accounts.map { ($0.accountId, base($0)) })
    var counts: [String: Int] = [:]
    for name in bases.values { counts[name, default: 0] += 1 }
    var names: [String: String] = [:]
    for a in accounts {
        let name = bases[a.accountId]!
        if counts[name]! > 1, let email = a.email, localPart(email) != name {
            names[a.accountId] = "\(name) · \(localPart(email))"
        } else if counts[name]! > 1 {
            names[a.accountId] = "\(name) · \(a.accountId.prefix(8))"
        } else {
            names[a.accountId] = name
        }
    }
    return names
}

/// Finder-style name order: case-insensitive, numbers compared by value ("toycrane 2" before "toycrane 10").
/// Ties (which display names rule out) fall back to the account id so the order is stable.
public func nameOrder(_ a: (name: String, id: String), _ b: (name: String, id: String)) -> Bool {
    switch a.name.localizedStandardCompare(b.name) {
    case .orderedAscending: return true
    case .orderedDescending: return false
    case .orderedSame: return a.id < b.id
    }
}

/// Accounts by display name, the order the panel, the "Remove account ›" menu, and `accounts` use.
public func sortedByName(_ accounts: [SavedAccount]) -> [SavedAccount] {
    let names = displayNames(accounts)
    return accounts.sorted { nameOrder((names[$0.accountId] ?? "", $0.accountId), (names[$1.accountId] ?? "", $1.accountId)) }
}

func writePrivate(_ data: Data, to url: URL) throws {
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try data.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
