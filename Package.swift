// swift-tools-version: 6.0
import Foundation
import PackageDescription

// With Command Line Tools only (no Xcode), SwiftPM intermittently omits the Swift Testing
// macro plugin path, failing with "plugin for module 'TestingMacros' not found".
// Pass it explicitly in that setup.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
        || !FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? []
    : [.unsafeFlags(["-plugin-path", cltTestingPlugins])]

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lumen", targets: ["Lumen"]),
    ],
    targets: [
        .target(name: "LumenCore"),
        .executableTarget(
            name: "Lumen",
            dependencies: ["LumenCore"]
        ),
        .testTarget(
            name: "LumenCoreTests",
            dependencies: ["LumenCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: testSwiftSettings
        ),
    ]
)
