import Foundation

/// Decides which file the lock screen can use for a video: the original when it is already HEVC,
/// otherwise a cached HEVC conversion stored in `LumenPaths.lockScreen`.
public struct LockScreenCache: Sendable {
    public let paths: LumenPaths

    public init(paths: LumenPaths) {
        self.paths = paths
    }

    public func cachedURL(for video: Video) -> URL {
        paths.lockScreen.appendingPathComponent("\(video.id.uuidString).mov")
    }

    /// The file to put in the lock screen slot, or `nil` while a conversion is still needed.
    public func readySource(for video: Video, originalURL: URL) -> URL? {
        if video.isHEVC {
            return originalURL
        }
        let cached = cachedURL(for: video)
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    public func needsConversion(_ video: Video) -> Bool {
        !video.isHEVC && !FileManager.default.fileExists(atPath: cachedURL(for: video).path)
    }

    public func removeCache(for video: Video) throws {
        let url = cachedURL(for: video)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
