import AppKit
import BatonCore

let arguments = CommandLine.arguments

// --status: what a switch would do right now, read-only. Prints no credentials.
if arguments.contains("--status") {
    let claude = ClaudePaths.live, paths = AppPaths.live
    let store = AccountStore(paths: paths)
    let current = ClaudeLog.current(claude.log)
    let accounts = store.all()
    let names = displayNames(accounts)
    let switcher = Switcher(claude: claude, paths: paths, store: store, app: LiveClaude())
    print("Claude running: \(LiveClaude().isRunning)")
    print("Signed in: \(current.map { names[$0.account] ?? "unsaved account \($0.account.prefix(8))" } ?? "nobody")")
    print("Saved accounts (\(accounts.count)):")
    for account in accounts { print("  \(account.accountId == current?.account ? "●" : " ") \(names[account.accountId]!)") }
    print("Legacy accounts available to import: \((try? FileManager.default.contentsOfDirectory(atPath: AppPaths.legacyAccounts.path).filter { $0.hasSuffix(".json") }.count) ?? 0)")
    print("Sessions working in the last 2 minutes: \(switcher.workingSessions())")
    let preview = SessionSync.run(paths.syncLocations(claude), preview: true)
    print("A switch now would sync: \(preview.summary)\(preview.notes.isEmpty ? "" : " (\(preview.notes.count) records left alone)")")
    exit(0)
}

// --snapshot <dir>: renders the panel in its main states, for review.
if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    MainActor.assumeIsolated { renderSnapshots(to: URL(fileURLWithPath: arguments[index + 1])) }
    exit(0)
}

// --iconset <dir>: writes the app icon for the build script.
if let index = arguments.firstIndex(of: "--iconset"), index + 1 < arguments.count {
    MainActor.assumeIsolated { AppIcon.writeIconset(to: URL(fileURLWithPath: arguments[index + 1])) }
    exit(0)
}

BatonApp.main()
