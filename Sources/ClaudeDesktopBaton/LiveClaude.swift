import AppKit
import BatonCore

/// The real Claude Desktop app.
final class LiveClaude: ClaudeApp, @unchecked Sendable {
    static let bundleId = "com.anthropic.claudefordesktop"

    static var appURL: URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) ?? URL(fileURLWithPath: "/Applications/Claude.app")
    }

    private var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId).filter { !$0.isTerminated }
    }

    var isRunning: Bool { !running.isEmpty }

    /// A normal quit, as from Claude's own menu; Claude saves its state first.
    func quit() { running.forEach { $0.terminate() } }

    func open() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: Self.appURL, configuration: configuration)
    }

    func open(link: URL) async throws {
        _ = try await NSWorkspace.shared.open([link], withApplicationAt: Self.appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
