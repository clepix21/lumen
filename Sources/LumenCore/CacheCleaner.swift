import Foundation

/// Frees disk space by removing what Lumen can rebuild or no longer uses:
/// lock screen HEVC conversions, and video or thumbnail files no library entry refers to.
/// Videos in the library, their thumbnails, `library.json` and its backups are never touched.
public struct CacheCleaner: Sendable {
    public let paths: LumenPaths

    public init(paths: LumenPaths) {
        self.paths = paths
    }

    /// Bytes that `clear(for:)` would free.
    public func cacheSize(for library: Library) -> Int64 {
        removableFiles(for: library).reduce(0) { $0 + size(of: $1) }
    }

    /// Removes the cache and orphan files; returns the bytes freed.
    @discardableResult
    public func clear(for library: Library) throws -> Int64 {
        var freed: Int64 = 0
        for url in removableFiles(for: library) {
            let bytes = size(of: url)
            try FileManager.default.removeItem(at: url)
            freed += bytes
        }
        return freed
    }

    private func removableFiles(for library: Library) -> [URL] {
        let usedVideos = Set(library.videos.map(\.fileName))
        let usedThumbnails = Set(library.videos.map { "\($0.id.uuidString).jpg" })
        return files(in: paths.lockScreen)
            + files(in: paths.videos).filter { !usedVideos.contains($0.lastPathComponent) }
            + files(in: paths.thumbnails).filter { !usedThumbnails.contains($0.lastPathComponent) }
    }

    private func files(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    }

    private func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
