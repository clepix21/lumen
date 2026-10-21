// swift-tools-version: 6.0
import PackageDescription

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
            dependencies: ["LumenCore"]
        ),
    ]
)
