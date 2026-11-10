import Foundation

/// A Claude Code session that a `claude remote-control` server is running on this Mac.
/// It has no record in Claude Desktop's session folders, so a switch cannot carry it:
/// it stays listed under the account that started its server. Only read, never changed.
public struct RemoteSession: Equatable, Sendable, Identifiable {
    /// The conversation's id, as `claude --resume` takes it.
    public let sessionId: String
    /// Where the session works: usually `<repo>/.claude/worktrees/bridge-cse_<id>`.
    public let folder: String
    /// The session's own title; nil while it only has the name derived from its folder.
    public let name: String?
    /// Another program on this Mac (a terminal, Claude Desktop) has the same conversation open.
    public let openElsewhere: Bool

    public init(sessionId: String, folder: String, name: String? = nil, openElsewhere: Bool = false) {
        self.sessionId = sessionId; self.folder = folder; self.name = name; self.openElsewhere = openElsewhere
    }

    public var id: String { sessionId }

    /// The repository the session belongs to: the folder that holds `.claude/worktrees`, else the folder itself.
    public var project: String {
        let path = folder.range(of: "/.claude/worktrees/").map { String(folder[..<$0.lowerBound]) } ?? folder
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// "dearly · Plan the memory layout", or the start of the id when the session has no title yet.
    public var title: String { "\(project) · \(name ?? String(sessionId.prefix(8)))" }

    /// Continues the conversation in a terminal, under whichever account the CLI is on.
    public var resumeCommand: String {
        "cd '\(folder.replacingOccurrences(of: "'", with: #"'\''"#))' && claude --resume \(sessionId)"
    }
}

/// Reads Claude Code's registry of running sessions (`~/.claude/sessions/<pid>.json`).
/// Undocumented; observed in Claude Code 2.1.319.
public enum RemoteSessions {
    /// Remote Control sessions whose process is still alive, by project and title.
    public static func running(registry: URL, isAlive: (Int32) -> Bool = processIsAlive) -> [RemoteSession] {
        struct Entry { let pid: Int32, sessionId: String, body: [String: Any] }
        var live: [Entry] = []
        for name in (try? FileManager.default.contentsOfDirectory(atPath: registry.path)) ?? [] where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: registry.appendingPathComponent(name)),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (body["pid"] as? NSNumber)?.int32Value, pid > 0,
                  let sessionId = body["sessionId"] as? String, isSafe(sessionId), isAlive(pid) else { continue }
            live.append(Entry(pid: pid, sessionId: sessionId, body: body))
        }
        var sessions: [RemoteSession] = []
        // A Remote Control server starts each session through the SDK and gives it a bridge id.
        for entry in live where entry.body["entrypoint"] as? String == "sdk-cli" {
            guard let bridge = entry.body["bridgeSessionId"] as? String, !bridge.isEmpty,
                  let folder = entry.body["cwd"] as? String, !folder.isEmpty,
                  !sessions.contains(where: { $0.sessionId == entry.sessionId }) else { continue }
            let named = entry.body["nameSource"] as? String != "derived"
            sessions.append(RemoteSession(
                sessionId: entry.sessionId, folder: folder,
                name: named ? (entry.body["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil,
                openElsewhere: live.contains { $0.sessionId == entry.sessionId && $0.pid != entry.pid }))
        }
        return sessions.sorted { ($0.project, $0.title, $0.sessionId) < ($1.project, $1.title, $1.sessionId) }
    }

    /// One resume command per line, for the clipboard.
    public static func resumeCommands(_ sessions: [RemoteSession]) -> String {
        sessions.map(\.resumeCommand).joined(separator: "\n")
    }

    /// The id ends up in a shell command, so only the characters Claude Code uses for ids pass.
    static func isSafe(_ sessionId: String) -> Bool {
        !sessionId.isEmpty && sessionId.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
