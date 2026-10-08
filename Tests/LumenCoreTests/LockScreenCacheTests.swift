import Foundation
import Testing
@testable import LumenCore

@Suite struct LockScreenCacheTests {
    @Test func hevcVideoUsesOriginal() throws {
        let cache = LockScreenCache(paths: try makeTempPaths())
        var video = makeVideo()
        video.isHEVC = true
        let original = URL(fileURLWithPath: "/tmp/original.mov")

        #expect(cache.readySource(for: video, originalURL: original) == original)
        #expect(!cache.needsConversion(video))
    }

    @Test func h264WithoutCacheNeedsConversion() throws {
        let cache = LockScreenCache(paths: try makeTempPaths())
        let video = makeVideo()

        #expect(cache.readySource(for: video, originalURL: URL(fileURLWithPath: "/tmp/original.mp4")) == nil)
        #expect(cache.needsConversion(video))
    }

    @Test func h264WithCacheUsesCache() throws {
        let cache = LockScreenCache(paths: try makeTempPaths())
        let video = makeVideo()
        try Data("hevc".utf8).write(to: cache.cachedURL(for: video))

        #expect(cache.readySource(for: video, originalURL: URL(fileURLWithPath: "/tmp/original.mp4")) == cache.cachedURL(for: video))
        #expect(!cache.needsConversion(video))
    }

    @Test func cachedFileIsNamedByVideoID() throws {
        let paths = try makeTempPaths()
        let video = makeVideo()
        #expect(LockScreenCache(paths: paths).cachedURL(for: video)
            == paths.lockScreen.appendingPathComponent("\(video.id.uuidString).mov"))
    }

    @Test func removeCacheDeletesFile() throws {
        let cache = LockScreenCache(paths: try makeTempPaths())
        let video = makeVideo()
        try Data("hevc".utf8).write(to: cache.cachedURL(for: video))

        try cache.removeCache(for: video)

        #expect(!FileManager.default.fileExists(atPath: cache.cachedURL(for: video).path))
        try cache.removeCache(for: video)
    }
}
