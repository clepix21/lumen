import Foundation

/// Locations of everything Lumen stores on disk.
public struct LumenPaths: Sendable {
    public let root: URL
    public let videos: URL
    public let thumbnails: URL
    public let lockScreen: URL
    public let libraryFile: URL

    public init(root: URL) {
        self.root = root
        videos = root.appendingPathComponent("Videos", isDirectory: true)
        thumbnails = root.appendingPathComponent("Thumbnails", isDirectory: true)
        lockScreen = root.appendingPathComponent("LockScreen", isDirectory: true)
        libraryFile = root.appendingPathComponent("library.json")
    }

    /// `~/Library/Application Support/Lumen`, or the folder in the `LUMEN_LIBRARY_DIR`
    /// environment variable (development and demos, without touching the real library).
    public static func standard() -> LumenPaths {
        if let custom = ProcessInfo.processInfo.environment["LUMEN_LIBRARY_DIR"], !custom.isEmpty {
            return LumenPaths(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LumenPaths(root: support.appendingPathComponent("Lumen", isDirectory: true))
    }

    public func createDirectories() throws {
        for directory in [root, videos, thumbnails, lockScreen] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
