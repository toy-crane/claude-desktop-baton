import Foundation

/// Where one sync pass reads and writes. The staging and trash folders belong to
/// Claude Desktop Baton and must be on the same volume as the sessions root.
public struct SyncLocations: Sendable {
    public let sessionsRoot: URL
    public let stagingDir: URL
    public let trashDir: URL

    public init(sessionsRoot: URL, stagingDir: URL, trashDir: URL) {
        self.sessionsRoot = sessionsRoot
        self.stagingDir = stagingDir
        self.trashDir = trashDir
    }
}

public struct SyncReport: Sendable, Equatable {
    public var created = 0
    public var updated = 0
    public var trashed = 0
    public var hintsUpdated = 0
    /// Set when the pass stopped before changing anything.
    public var aborted: String?
    /// Records left alone, and writes that failed, with the reason.
    public var notes: [String] = []

    public var changed: Int { created + updated + trashed }
    public var summary: String {
        if let aborted { return "Sessions not synced: \(aborted)" }
        return "\(created) added, \(updated) updated, \(trashed) removed"
    }
}

/// Brings Code session records in line across every account folder.
/// Rules: docs/decisions/session-sync.md.
public enum SessionSync {
    public static let archivedWindow: TimeInterval = 30 * 24 * 60 * 60
    /// Claude Desktop skips record files above this size, so a larger one is not mirrored.
    static let maxRecordBytes = 10 * 1024 * 1024
    static let hintFile = "archived-sessions.idx"

    /// One pass over every account folder. Call only while Claude Desktop is closed:
    /// Claude keeps the loaded folder in memory and overwrites outside changes.
    /// With `preview`, counts what would change and writes nothing.
    ///
    /// Folders hold thousands of large records, so the pass works from file sizes and
    /// modification times and reads a record only when its copies may differ. Copies this
    /// pass writes keep the winner's modification time, so matching copies stay matching.
    public static func run(_ locations: SyncLocations, now: Date = Date(), preview: Bool = false) -> SyncReport {
        var report = SyncReport()
        var folders: [Folder]
        do { folders = try scan(locations.sessionsRoot) } catch {
            report.aborted = "the session folders could not be read"
            return report
        }

        var cache: [URL: Result<Record, Reason>] = [:]
        func parsed(_ entry: Entry) -> Result<Record, Reason> {
            if let hit = cache[entry.url] { return hit }
            let result = autoreleasepool { readRecord(entry) }
            cache[entry.url] = result
            return result
        }

        enum Action {
            case trash(folder: Int, entry: Entry)
            case write(winner: Record, folder: Int, existing: Entry?)
        }
        var actions: [Action] = []
        let deleted = Set(folders.flatMap(\.deletedMarkers))
        let cutoff = now.addingTimeInterval(-archivedWindow)

        let ids = Set(folders.flatMap { $0.entries.keys }).sorted()
        for id in ids {
            if deleted.contains(id) {
                for (index, folder) in folders.enumerated() {
                    if let entry = folder.entries[id] { actions.append(.trash(folder: index, entry: entry)) }
                }
                continue
            }
            // Folders that can receive this session: not holding a copy Claude would not load.
            var targets = folders.indices.filter { folders[$0].unreadable[id] == nil }
            let first = targets.first.flatMap { folders[$0].entries[id] }
            if let first, targets.allSatisfy({ folders[$0].entries[id].map { $0.sameFile(as: first) } ?? false }) { continue }

            var copies: [(Int, Record)] = []
            for index in targets {
                guard let entry = folders[index].entries[id] else { continue }
                switch parsed(entry) {
                case .success(let record): copies.append((index, record))
                case .failure(let reason): folders[index].unreadable[id] = reason.text
                }
            }
            targets = targets.filter { folders[$0].unreadable[id] == nil }
            guard let (winnerIndex, winner) = copies.max(by: { isOlder($0.1, than: $1.1) }) else { continue }
            if winner.isArchived && winner.lastActivity < cutoff { continue }

            for index in targets where index != winnerIndex {
                let existing = folders[index].entries[id]
                if let existing, existing.sameFile(as: winner.entry) || sameContents(existing, winner.entry) { continue }
                actions.append(.write(winner: winner, folder: index, existing: existing))
            }
        }

        let files = folders.reduce(0) { total, folder in
            total + folder.entries.count + folder.unreadable.keys.filter { folder.entries[$0] == nil }.count
        }
        let unreadable = folders.reduce(0) { $0 + $1.unreadable.count }
        if files > 0 && (files - unreadable) * 2 < files {
            report.aborted = "only \(files - unreadable) of \(files) session files look familiar"
            return report
        }
        for folder in folders {
            for (id, reason) in folder.unreadable.sorted(by: { $0.key < $1.key }) {
                report.notes.append("\(folder.key)/\(id): \(reason)")
            }
        }

        let stamp = Self.stamp(now)
        var placed: [Int: [String: Bool]] = [:]   // folder -> id -> isArchived of the copy placed there
        var removed: [Int: Set<String>] = [:]      // folder -> ids moved to trash
        for action in actions {
            switch action {
            case .trash(let index, let entry):
                do {
                    if !preview { try moveToTrash(entry, folder: folders[index], locations: locations, stamp: stamp) }
                    report.trashed += 1
                    removed[index, default: []].insert(entry.id)
                } catch {
                    report.notes.append("\(folders[index].key)/\(entry.id): could not move to trash (\(error.localizedDescription))")
                }
            case .write(let winner, let index, let existing):
                do {
                    if !preview { try place(winner, in: folders[index], replacing: existing, locations: locations) }
                    if existing == nil { report.created += 1 } else { report.updated += 1 }
                    placed[index, default: [:]][winner.entry.id] = winner.isArchived
                } catch {
                    report.notes.append("\(folders[index].key)/\(winner.entry.id): could not be written (\(error.localizedDescription))")
                }
            }
        }

        // Claude's archived-session hint: start from Claude's own list and apply this pass's changes.
        for (index, folder) in folders.enumerated() {
            let placedHere = placed[index] ?? [:], removedHere = removed[index] ?? []
            guard let hint = folder.hint, !placedHere.isEmpty || !removedHere.isEmpty else { continue }
            var archived = Set(hint)
            for (id, isArchived) in placedHere {
                if isArchived { archived.insert(id) } else { archived.remove(id) }
            }
            archived.subtract(removedHere)
            let desired = archived.sorted()
            guard desired != hint.sorted() else { continue }
            do {
                if !preview { try writeHint(desired, in: folder, locations: locations) }
                report.hintsUpdated += 1
            } catch {
                report.notes.append("\(folder.key): archived list could not be updated")
            }
        }
        return report
    }

    // MARK: reading

    /// A record file as listed: enough to tell whether two copies are the same file.
    struct Entry: Equatable {
        let id: String          // "local_<uuid>"
        let url: URL
        let size: Int
        let modified: Date

        /// Times compare to the millisecond: copies made by other tools keep only millisecond precision.
        func sameFile(as other: Entry) -> Bool {
            size == other.size && abs(modified.timeIntervalSince(other.modified)) < 0.001
        }
    }

    /// The fields the sync needs, read from a record's JSON. The bytes are not kept.
    struct Record {
        let entry: Entry
        let lastActivity: Date
        let isArchived: Bool
    }

    struct Folder {
        let key: String
        let url: URL
        var entries: [String: Entry] = [:]
        /// Records Claude would not load, or that may be someone else's: never a source or target.
        var unreadable: [String: String] = [:]
        var deletedMarkers: [String] = []   // as record ids, "local_<uuid>"
        /// The archived-session hint, when it exists and has the expected shape.
        var hint: [String]?
    }

    static func isOlder(_ a: Record, than b: Record) -> Bool {
        if a.lastActivity != b.lastActivity { return a.lastActivity < b.lastActivity }
        return a.entry.modified < b.entry.modified
    }

    static func sameContents(_ a: Entry, _ b: Entry) -> Bool {
        autoreleasepool {
            guard a.size == b.size, let x = try? Data(contentsOf: a.url), let y = try? Data(contentsOf: b.url) else { return false }
            return x == y
        }
    }

    static let uuid = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    static let recordName = try! NSRegularExpression(pattern: "^(local_\(uuid))\\.json$")
    static let markerName = try! NSRegularExpression(pattern: "^deleted_(\(uuid))$")
    static let uuidName = try! NSRegularExpression(pattern: "^\(uuid)$")

    static func match(_ regex: NSRegularExpression, _ text: String) -> String? {
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) { return String(text[r]) }
        return text
    }

    /// Real (not linked) directories named like UUIDs.
    static func uuidDirectories(_ url: URL) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: url.path).sorted().filter { name in
            guard match(uuidName, name) != nil,
                  let type = try? fm.attributesOfItem(atPath: url.appendingPathComponent(name).path)[.type] as? FileAttributeType
            else { return false }
            return type == .typeDirectory
        }
    }

    /// Lists every folder's records by file attributes only; nothing is read yet.
    static func scan(_ root: URL) throws -> [Folder] {
        var folders: [Folder] = []
        for account in try uuidDirectories(root) {
            let accountURL = root.appendingPathComponent(account)
            for org in try uuidDirectories(accountURL) {
                let url = accountURL.appendingPathComponent(org)
                var folder = Folder(key: "\(account)/\(org)", url: url)
                for name in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() {
                    if let uuid = match(markerName, name) {
                        folder.deletedMarkers.append("local_\(uuid)")
                    } else if let id = match(recordName, name) {
                        switch entry(url.appendingPathComponent(name), id: id) {
                        case .success(let entry): folder.entries[id] = entry
                        case .failure(let reason): folder.unreadable[id] = reason.text
                        case nil: break  // vanished while listing
                        }
                    }
                }
                folder.hint = readHint(url.appendingPathComponent(hintFile))
                folders.append(folder)
            }
        }
        return folders
    }

    struct Reason: Error { let text: String }

    static func entry(_ url: URL, id: String) -> Result<Entry, Reason>? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return .failure(Reason(text: "not a regular file")) }
        guard (attributes[.referenceCount] as? Int ?? 1) <= 1 else { return .failure(Reason(text: "hard-linked")) }
        let size = attributes[.size] as? Int ?? 0
        guard size <= maxRecordBytes else { return .failure(Reason(text: "too large")) }
        return .success(Entry(id: id, url: url, size: size, modified: attributes[.modificationDate] as? Date ?? .distantPast))
    }

    /// A record's JSON object, read through the same checks as the sync. Nil when Claude would not load it.
    static func fields(_ url: URL, id: String) -> [String: Any]? {
        guard case .success = entry(url, id: id) ?? .failure(Reason(text: "")),
              let bytes = try? Data(contentsOf: url),
              let body = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              body["sessionId"] as? String == id else { return nil }
        return body
    }

    static func readRecord(_ entry: Entry) -> Result<Record, Reason> {
        guard let bytes = try? Data(contentsOf: entry.url) else { return .failure(Reason(text: "unreadable")) }
        guard let body = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            return .failure(Reason(text: "not a JSON object"))
        }
        guard body["sessionId"] as? String == entry.id else { return .failure(Reason(text: "session id does not match the file name")) }
        let activity = (body["lastActivityAt"] as? NSNumber)?.doubleValue ?? 0
        return .success(Record(entry: entry, lastActivity: Date(timeIntervalSince1970: activity / 1000),
                               isArchived: body["isArchived"] as? Bool == true))
    }

    static func readHint(_ url: URL) -> [String]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let data = try? Data(contentsOf: url),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["v"] as? Int == 1, let ids = body["archived"] as? [String] else { return nil }
        return ids
    }

    // MARK: writing

    /// Claude's folders only ever see a complete ordinary file: content is prepared
    /// in our own staging folder and renamed into place.
    static func stage(_ data: Data, modified: Date?, locations: SyncLocations) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: locations.stagingDir, withIntermediateDirectories: true)
        let temp = locations.stagingDir.appendingPathComponent("\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw Reason(text: "staging failed")
        }
        if let modified { try fm.setAttributes([.modificationDate: modified], ofItemAtPath: temp.path) }
        return temp
    }

    static func renameIntoPlace(_ temp: URL, _ target: URL) throws {
        guard Darwin.rename(temp.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw Reason(text: String(cString: strerror(errno)))
        }
    }

    static func place(_ winner: Record, in folder: Folder, replacing existing: Entry?, locations: SyncLocations) throws {
        let source = winner.entry
        let target = folder.url.appendingPathComponent(source.url.lastPathComponent)
        // Something changed the target since the scan: leave it for the next switch.
        if let existing {
            let now = try? FileManager.default.attributesOfItem(atPath: target.path)
            guard now?[.modificationDate] as? Date == existing.modified, now?[.size] as? Int == existing.size else {
                throw Reason(text: "changed during the pass")
            }
        } else if FileManager.default.fileExists(atPath: target.path) {
            throw Reason(text: "appeared during the pass")
        }
        // The winner itself must still be what the scan saw.
        guard case .success(let current)? = entry(source.url, id: source.id), current.sameFile(as: source),
              let bytes = try? Data(contentsOf: source.url) else { throw Reason(text: "source changed during the pass") }
        try renameIntoPlace(try stage(bytes, modified: source.modified, locations: locations), target)
    }

    static func moveToTrash(_ record: Entry, folder: Folder, locations: SyncLocations, stamp: String) throws {
        let destination = locations.trashDir.appendingPathComponent(stamp).appendingPathComponent(folder.key)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: record.url, to: destination.appendingPathComponent(record.url.lastPathComponent))
    }

    static func writeHint(_ ids: [String], in folder: Folder, locations: SyncLocations) throws {
        let data = try JSONSerialization.data(withJSONObject: ["v": 1, "archived": ids] as [String: Any],
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        try renameIntoPlace(try stage(data, modified: nil, locations: locations), folder.url.appendingPathComponent(hintFile))
    }

    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
