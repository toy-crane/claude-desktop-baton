// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeDesktopBaton",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ClaudeDesktopBaton", targets: ["ClaudeDesktopBaton"])
    ],
    dependencies: [
        // App updates (docs/decisions/app-updates.md). Pinned; scripts/build-app.sh embeds and signs the framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(
            name: "BatonCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ClaudeDesktopBaton",
            dependencies: ["BatonCore", .product(name: "Sparkle", package: "Sparkle")],
            // Finds Sparkle.framework in the app bundle's Contents/Frameworks, also when run through the ~/.local/bin link.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "BatonCoreTests",
            dependencies: ["BatonCore"]
        ),
    ]
)
