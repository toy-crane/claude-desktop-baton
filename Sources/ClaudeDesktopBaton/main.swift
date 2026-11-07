import AppKit
import BatonCore

let arguments = CommandLine.arguments

// The command line for agents and scripts: `claude-desktop-baton <command>` through the PATH link,
// or the app's executable with a command. `--status` is kept from before and means `status`.
let invokedAsCommand = URL(fileURLWithPath: arguments[0]).lastPathComponent == AgentCommand.commandName
let commandArguments = arguments.dropFirst().map { $0 == "--status" ? "status" : $0 }
if invokedAsCommand || commandArguments.first.map(AgentCommand.names.contains) == true {
    let finished = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var output = AgentOutput(text: "", code: AgentCommand.Exit.error)
    Task.detached {
        output = await AgentCommand.run(Array(commandArguments), LiveAgent.context())
        finished.signal()
    }
    finished.wait()
    let text = output.text.hasSuffix("\n") || output.text.isEmpty ? output.text : output.text + "\n"
    // JSON always goes to stdout so agents can parse it; plain-text errors go to stderr.
    let toStdout = output.code == 0 || commandArguments.contains("--json")
    FileHandle(fileDescriptor: toStdout ? STDOUT_FILENO : STDERR_FILENO).write(Data(text.utf8))
    exit(output.code)
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
