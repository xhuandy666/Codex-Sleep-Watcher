// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSleepWatcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexSleepWatcherCore", targets: ["CodexSleepWatcherCore"]),
        .executable(name: "CodexSleepWatcherApp", targets: ["CodexSleepWatcherApp"]),
        .executable(name: "codex-sleep-hook", targets: ["CodexSleepHook"]),
        .executable(name: "codex-sleep-tests", targets: ["CodexSleepWatcherTests"]),
    ],
    targets: [
        .target(name: "CodexSleepWatcherCore"),
        .executableTarget(name: "CodexSleepWatcherApp", dependencies: ["CodexSleepWatcherCore"]),
        .executableTarget(name: "CodexSleepHook", dependencies: ["CodexSleepWatcherCore"]),
        .executableTarget(name: "CodexSleepWatcherTests", dependencies: ["CodexSleepWatcherCore"]),
    ]
)
