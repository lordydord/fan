// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "FanCore", targets: ["FanCore"])],
    targets: [
        .target(name: "FanCore", path: "fan/Core",
                exclude: ["BatteryMonitor.swift", "FanController.swift", "LaunchAtLoginManager.swift",
                          "PermissionsManager.swift", "StatusBarManager.swift", "SystemMonitor.swift",
                          "UserDefaultsManager.swift"],
                sources: ["FanControlPolicy.swift", "PowerReadingPolicy.swift"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore"], path: "fanPolicyTests")
    ]
)
