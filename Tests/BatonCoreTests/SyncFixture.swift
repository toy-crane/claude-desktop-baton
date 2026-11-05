import Foundation
@testable import BatonCore

/// A throwaway copy of Claude's session layout: claude-code-sessions/<account>/<org>/.
final class SyncFixture {
    static let accountA = "aaaaaaaa-0000-4000-8000-000000000001"
    static let accountB = "bbbbbbbb-0000-4000-8000-000000000002"
    static let org = "0000000f-0000-4000-8000-00000000000f"
    static var folderA: String { "\(accountA)/\(org)" }
    static var folderB: String { "\(accountB)/\(org)" }

    let root: URL
    let locations: SyncLocations
    let now = Date(timeIntervalSince1970: 1_793_000_000)

    init(folders: [String] = [SyncFixture.folderA, SyncFixture.folderB]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("baton-sync-\(UUID().uuidString)")
        let sessions = root.appendingPathComponent("claude-code-sessions")
        let work = root.appendingPathComponent("work")
        locations = SyncLocations(sessionsRoot: sessions,
                                  stagingDir: work.appendingPathComponent("staging"),
                                  trashDir: work.appendingPathComponent("trash"))
        for folder in folders {
            try FileManager.default.createDirectory(at: sessions.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func dir(_ folder: String) -> URL { locations.sessionsRoot.appendingPathComponent(folder) }
    func recordURL(_ folder: String, _ uuid: String) -> URL { dir(folder).appendingPathComponent("local_\(uuid).json") }

    /// Writes a record the way Claude does, with a given activity time and file modification time.
    @discardableResult
    func writeRecord(_ folder: String, _ uuid: String, daysAgo: Double, archived: Bool = false,
                     title: String = "session", modifiedDaysAgo: Double? = nil) throws -> Data {
        let activity = now.addingTimeInterval(-daysAgo * 86_400)
        let body: [String: Any] = [
            "sessionId": "local_\(uuid)",
            "lastActivityAt": Int64(activity.timeIntervalSince1970 * 1000),
            "isArchived": archived,
            "title": title,
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let url = recordURL(folder, uuid)
        try data.write(to: url)
        let mtime = now.addingTimeInterval(-(modifiedDaysAgo ?? daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: mtime, .posixPermissions: 0o600], ofItemAtPath: url.path)
        return data
    }

    func writeRaw(_ folder: String, name: String, _ text: String) throws {
        try Data(text.utf8).write(to: dir(folder).appendingPathComponent(name))
    }

    func markDeleted(_ folder: String, _ uuid: String) throws {
        try writeRaw(folder, name: "deleted_\(uuid)", String(Int64(now.timeIntervalSince1970 * 1000)))
    }

    func read(_ folder: String, _ uuid: String) -> Data? { try? Data(contentsOf: recordURL(folder, uuid)) }

    func title(_ folder: String, _ uuid: String) -> String? {
        guard let data = read(folder, uuid),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["title"] as? String
    }

    func modified(_ folder: String, _ uuid: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: recordURL(folder, uuid).path))?[.modificationDate] as? Date
    }

    func mode(_ folder: String, _ uuid: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: recordURL(folder, uuid).path))?[.posixPermissions] as? Int
    }

    func trashedCopies(of uuid: String) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: locations.trashDir, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent == "local_\(uuid).json" }
    }

    func files(_ folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir(folder).path)) ?? []).sorted()
    }

    func archivedHint(_ folder: String) -> [String]? {
        guard let data = try? Data(contentsOf: dir(folder).appendingPathComponent("archived-sessions.idx")),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["archived"] as? [String]
    }

    @discardableResult
    func sync() -> SyncReport { SessionSync.run(locations, now: now) }
}
