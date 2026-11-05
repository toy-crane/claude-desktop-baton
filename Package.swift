// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeDesktopBaton",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ClaudeDesktopBaton", targets: ["ClaudeDesktopBaton"])
    ],
    targets: [
        .target(
            name: "BatonCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ClaudeDesktopBaton",
            dependencies: ["BatonCore"]
        ),
        .testTarget(
            name: "BatonCoreTests",
            dependencies: ["BatonCore"]
        ),
    ]
)
