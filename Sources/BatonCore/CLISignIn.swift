import Foundation
import Security

/// The Claude Code CLI's Keychain item ("Claude Code-credentials"). Besides the login it holds the
/// CLI's MCP server tokens, so only its `claudeAiOauth` entry is ever replaced.
public protocol CLICredentialStore: Sendable {
    /// The whole item as JSON, or nil when there is none.
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// Claude Desktop Baton's own Keychain items for saved CLI sign-ins, one per account id.
public protocol SecretStore: Sendable {
    func load(_ key: String) -> Data?
    func save(_ key: String, _ data: Data) throws
    func delete(_ key: String)
    /// Which keys exist, without reading any secret.
    func keys() -> Set<String>
}

/// Where the default CLI config lives (no `CLAUDE_CONFIG_DIR`).
public struct CLIPaths: Sendable {
    /// `~/.claude`
    public let configHome: URL
    /// `~/.claude.json`
    public let globalConfig: URL

    public init(configHome: URL, globalConfig: URL) { self.configHome = configHome; self.globalConfig = globalConfig }

    public static let live = CLIPaths(
        configHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
        globalConfig: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"))

    /// Claude Code's token-refresh locks, taken in this order (proper-lockfile directories, stale after 60 s).
    public var refreshLock: URL { configHome.appendingPathComponent(".oauth_refresh.lock") }
    public var legacyRefreshLock: URL { configHome.deletingLastPathComponent().appendingPathComponent(configHome.lastPathComponent + ".lock") }
    /// Claude Code's lock for `~/.claude.json` (stale after 10 s).
    public var configLock: URL { globalConfig.deletingLastPathComponent().appendingPathComponent(globalConfig.lastPathComponent + ".lock") }
}

/// Who the CLI is signed in as.
public enum CLIState: Equatable, Sendable {
    case signedOut
    case account(Identity)

    public var identity: Identity? { if case .account(let id) = self { return id }; return nil }
}

public enum CLIFollow: Equatable, Sendable {
    /// The CLI now uses the target account.
    case moved
    /// The CLI was already on the target account.
    case alreadyThere
    /// No CLI sign-in is saved for the target; the CLI was left as it was.
    case notSaved(cli: CLIState)
    /// Moving failed; the CLI was left as it was.
    case failed(String)
}

/// Saves each account's CLI sign-in and moves the CLI between them.
public final class CLIAccounts: @unchecked Sendable {
    public let paths: CLIPaths
    let credentials: CLICredentialStore
    let saved: SecretStore
    let store: AccountStore
    let lockTimeout: TimeInterval

    public init(paths: CLIPaths, credentials: CLICredentialStore, saved: SecretStore, store: AccountStore, lockTimeout: TimeInterval = 10) {
        self.paths = paths; self.credentials = credentials; self.saved = saved; self.store = store; self.lockTimeout = lockTimeout
    }

    static let loginKey = "claudeAiOauth", accountKey = "oauthAccount"

    /// From `~/.claude.json` only; reads no secret.
    public func current() -> CLIState {
        guard let account = readConfig()?[Self.accountKey] as? [String: Any] else { return .signedOut }
        return Self.identity(account).map(CLIState.account) ?? .signedOut
    }

    /// Saves the CLI's sign-in when it belongs to a saved account. Returns that account id.
    @discardableResult
    public func saveCurrent() -> String? {
        guard let config = readConfig(), let account = config[Self.accountKey] as? [String: Any],
              let identity = Self.identity(account),
              let saved = store.load(identity.account), saved.orgId == identity.org,
              let item = try? credentials.read(),
              let login = (try? JSONSerialization.jsonObject(with: item) as? [String: Any])?[Self.loginKey] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: [Self.loginKey: login, Self.accountKey: account], options: .sortedKeys)
        else { return nil }
        if self.saved.load(saved.accountId) != data { try? self.saved.save(saved.accountId, data) }
        return saved.accountId
    }

    public func hasSavedSignIn(_ accountId: String) -> Bool { saved.keys().contains(accountId) }
    public func accountsWithSavedSignIn() -> Set<String> { saved.keys() }

    /// Re-saves the outgoing CLI sign-in, then puts the target's in place under Claude Code's own locks,
    /// so a refresh in a running CLI cannot write the old account back.
    public func follow(_ target: SavedAccount) -> CLIFollow {
        let state = current()
        guard let data = saved.load(target.accountId),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = entry[Self.loginKey] as? [String: Any], let account = entry[Self.accountKey] as? [String: Any]
        else {
            saveCurrent()
            return .notSaved(cli: state)
        }
        if state.identity == target.identity {
            saveCurrent()
            return .alreadyThere
        }

        // The same order Claude Code takes them: the refresh lock, then the legacy one; then the config lock.
        let locks = [(paths.refreshLock, 60.0), (paths.legacyRefreshLock, 60.0), (paths.configLock, 10.0)]
        var held: [DirectoryLock] = []
        defer { held.reversed().forEach { $0.release() } }
        for (url, stale) in locks {
            guard let lock = DirectoryLock.acquire(url, stale: stale, timeout: lockTimeout) else {
                return .failed("Claude Code kept its sign-in locked, so the CLI stayed where it was. Try the switch again.")
            }
            held.append(lock)
        }
        // Saved under the locks, so a refresh that finished while this waited is the token kept.
        saveCurrent()

        let previousItem: Data?
        do { previousItem = try credentials.read() } catch { return .failed("The CLI's Keychain item could not be read.") }
        var item: [String: Any] = [:]
        if let previousItem {
            // The item also holds the CLI's MCP tokens; one that cannot be read is never replaced.
            guard let parsed = (try? JSONSerialization.jsonObject(with: previousItem)) as? [String: Any] else {
                return .failed("The CLI's Keychain item is in a format this app does not know, so it was left alone.")
            }
            item = parsed
        }
        guard var config = readConfig() else { return .failed("~/.claude.json could not be read.") }
        item[Self.loginKey] = login
        config[Self.accountKey] = account
        do {
            try credentials.write(JSONSerialization.data(withJSONObject: item))
        } catch {
            return .failed("The CLI's Keychain item could not be written.")
        }
        do {
            try writeConfig(config)
        } catch {
            if let previousItem { try? credentials.write(previousItem) }
            return .failed("~/.claude.json could not be written.")
        }
        return .moved
    }

    public func forget(_ accountId: String) { saved.delete(accountId) }

    // MARK: files

    static func identity(_ account: [String: Any]) -> Identity? {
        guard let id = account["accountUuid"] as? String, let org = account["organizationUuid"] as? String else { return nil }
        return Identity(account: id, org: org)
    }

    private func readConfig() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: paths.globalConfig))) as? [String: Any]
    }

    /// Keeps every other setting and the file's permissions; written to a temp file and renamed.
    private func writeConfig(_ config: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])
        let mode = (try? FileManager.default.attributesOfItem(atPath: paths.globalConfig.path))?[.posixPermissions] as? Int ?? 0o600
        let temp = paths.globalConfig.deletingLastPathComponent().appendingPathComponent(".claude.json.baton-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: mode]) else {
            throw BatonError("~/.claude.json could not be written.")
        }
        guard rename(temp.path, paths.globalConfig.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw BatonError("~/.claude.json could not be replaced.")
        }
    }
}

/// A lock Claude Code understands: a directory created with mkdir (npm proper-lockfile). One left by a
/// process that died is taken over once its modification time is older than `stale`.
final class DirectoryLock {
    let url: URL
    private init(_ url: URL) { self.url = url }

    static func acquire(_ url: URL, stale: TimeInterval, timeout: TimeInterval) -> DirectoryLock? {
        let deadline = Date().addingTimeInterval(timeout)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        while true {
            if mkdir(url.path, 0o755) == 0 { return DirectoryLock(url) }
            guard errno == EEXIST else { return nil }
            if let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > stale {
                rmdir(url.path)
                continue
            }
            guard Date() < deadline else { return nil }
            usleep(100_000)
        }
    }

    func release() { rmdir(url.path) }
}

// MARK: live stores

/// The CLI's own Keychain item, read and written through `/usr/bin/security` as Claude Code does,
/// so the item's access list (which trusts `security`) never prompts. Writes go through stdin when they fit.
public struct SecurityCLICredentials: CLICredentialStore {
    public let service: String
    public let account: String

    public init(service: String = "Claude Code-credentials", account: String = NSUserName()) {
        self.service = service; self.account = account
    }

    public func read() throws -> Data? {
        let result = try Self.run(["find-generic-password", "-a", account, "-s", service, "-w"])
        if result.status == 44 { return nil }
        guard result.status == 0 else { throw BatonError("The CLI's Keychain item could not be read (\(result.status)).") }
        var output = result.output
        while output.last == 0x0A { output.removeLast() }
        return Self.decode(output)
    }

    /// `security -w` prints the value itself, or hex when it holds bytes it deems unprintable.
    static func decode(_ output: Data) -> Data {
        guard output.first != UInt8(ascii: "{"), output.count % 2 == 0,
              let text = String(data: output, encoding: .ascii), text.allSatisfy(\.isHexDigit) else { return output }
        var bytes = Data(capacity: output.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return output }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    public func write(_ data: Data) throws {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let line = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \(hex)\n"
        // `security -i` reads one line of at most 4096 bytes; larger items go through arguments, as Claude Code does.
        let result = line.utf8.count < 4000
            ? try Self.run(["-i"], input: Data(line.utf8))
            : try Self.run(["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex])
        guard result.status == 0 else { throw BatonError("The CLI's Keychain item could not be written (\(result.status)).") }
    }

    static func run(_ arguments: [String], input: Data? = nil) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let out = Pipe(), inPipe = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = input == nil ? FileHandle.nullDevice : inPipe
        try process.run()
        if let input {
            inPipe.fileHandleForWriting.write(input)
            try? inPipe.fileHandleForWriting.close()
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}

/// Claude Desktop Baton's own Keychain items, created by the app, so the app reads them without a prompt.
public struct KeychainSecrets: SecretStore {
    public let service: String
    public init(service: String = "Claude Desktop Baton CLI sign-in") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    public func load(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
    }

    public func save(_ key: String, _ data: Data) throws {
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(key)
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = service
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw BatonError("The CLI sign-in could not be saved.") }
        } else if status != errSecSuccess {
            throw BatonError("The CLI sign-in could not be saved (\(status)).")
        }
    }

    public func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }

    public func keys() -> Set<String> {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var items: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &items) == errSecSuccess, let list = items as? [[String: Any]] else { return [] }
        return Set(list.compactMap { $0[kSecAttrAccount as String] as? String })
    }
}
