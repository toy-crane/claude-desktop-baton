import AppKit
import BatonCore

/// The command line's view of the real system. Reads run here; a switch goes to the menu bar app.
enum LiveAgent {
    static let bundleId = "com.toycrane.claude-desktop-baton"

    static func context() -> AgentContext {
        let claude = ClaudePaths.live, paths = AppPaths.live
        let store = AccountStore(paths: paths)
        let client = UsageClient(userAgent: ClaudeKeychain.userAgent(claudeApp: LiveClaude.appURL),
                                 key: { try ClaudeKeychain.cookieKey() })
        return AgentContext(
            claude: claude, store: store,
            usage: UsageReader(cache: UsageCache(file: paths.usageCache), client: client, claude: claude),
            environment: ProcessInfo.processInfo.environment,
            status: {
                let switcher = Switcher(claude: claude, paths: paths, store: store, app: LiveClaude())
                let legacy = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.legacyAccounts.path))?
                    .filter { $0.hasSuffix(".json") }.count ?? 0
                let preview = SessionSync.run(paths.syncLocations(claude), preview: true)
                let notes = preview.notes.isEmpty ? "" : " (\(preview.notes.count) records left alone)"
                return StatusFacts(claudeRunning: LiveClaude().isRunning,
                                   menuBarAppRunning: ControlClient.isListening(paths.controlSocket),
                                   workingSessions: switcher.workingSessions(), legacyImportable: legacy,
                                   syncPreview: preview.summary + notes)
            },
            requestSwitch: { request, wait in await requestSwitch(request, wait: wait, socket: paths.controlSocket) })
    }

    /// Hands the switch to the menu bar app, launching it first when nothing is listening.
    static func requestSwitch(_ request: ControlRequest, wait: Bool, socket: URL) async -> Result<ControlResponse, ControlError> {
        if !ControlClient.isListening(socket) {
            guard launchApp() else { return .failure(.unreachable) }
            let deadline = Date().addingTimeInterval(20)
            while !ControlClient.isListening(socket) {
                guard Date() < deadline else { return .failure(.unreachable) }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        return await Task.detached {
            do throws(ControlError) {
                return .success(try ControlClient.send(request, socket: socket, wait: wait, timeout: 180))
            } catch {
                return .failure(error)
            }
        }.value
    }

    /// The app this command belongs to: the bundle around the executable (through the PATH link),
    /// else the installed copy.
    static var appURL: URL? {
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension == "app" { return bundle }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    /// Launches the menu bar app in the background, as Finder would.
    static func launchApp() -> Bool {
        guard let appURL else { return false }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", appURL.path]
        do { try open.run() } catch { return false }
        open.waitUntilExit()
        return open.terminationStatus == 0
    }
}

/// The `claude-desktop-baton` link in `~/.local/bin` that puts the command on the PATH.
enum CommandLineTool {
    enum State: Equatable { case installed, missing, broken, occupied }

    static var link: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(AgentCommand.commandName)")
    }

    static var target: URL? { Bundle.main.executableURL?.resolvingSymlinksInPath() }

    static var state: State {
        let fm = FileManager.default
        if let destination = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            let resolved = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent()).resolvingSymlinksInPath()
            return resolved.path == target?.path && fm.isExecutableFile(atPath: resolved.path) ? .installed : .broken
        }
        return fm.fileExists(atPath: link.path) ? .occupied : .missing
    }

    /// Creates the link; replaces a link that points elsewhere, never a real file.
    static func install() throws {
        guard let target else { throw BatonError("The app's own executable could not be found.") }
        let fm = FileManager.default
        switch state {
        case .installed: return
        case .occupied: throw BatonError("A different file already exists at ~/.local/bin/\(AgentCommand.commandName), so it was left alone.")
        case .broken: try fm.removeItem(at: link)
        case .missing: break
        }
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
    }

    /// Whether the user's login shell finds commands in `~/.local/bin`; nil when the shell could not be asked.
    static func isOnPath() -> Bool? {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        shell.arguments = ["-ilc", "printf '%s' \"$PATH\""]
        let output = Pipe()
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        shell.standardInput = FileHandle.nullDevice
        do { try shell.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(5)
        while shell.isRunning, Date() < deadline { usleep(50_000) }
        if shell.isRunning { shell.terminate(); return nil }
        let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let dir = link.deletingLastPathComponent().path
        return path.split(separator: ":").contains { ($0 as NSString).expandingTildeInPath == dir }
    }
}
