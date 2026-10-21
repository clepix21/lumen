import Foundation
import Testing
@testable import LumenCore

@Suite struct CacheCleanerTests {
    struct Setup {
        let paths: LumenPaths
        let library: Library
        let kept: [URL]
        let removable: [URL]
    }

    /// A library with one video, plus a lock screen conversion and orphan files.
    func makeSetup() throws -> Setup {
        let paths = try makeTempPaths()
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let importer = VideoImporter(paths: paths)

        let videoFile = importer.fileURL(for: video)
        let thumbnail = importer.thumbnailURL(for: video.id)
        let conversion = LockScreenCache(paths: paths).cachedURL(for: video)
        let orphanVideo = paths.videos.appendingPathComponent("\(UUID().uuidString).mp4")
        let orphanThumbnail = paths.thumbnails.appendingPathComponent("\(UUID().uuidString).jpg")
        let corruptBackup = paths.root.appendingPathComponent("library.corrupt-20261021-100000.json")

        try Data(count: 1_000).write(to: videoFile)
        try Data(count: 100).write(to: thumbnail)
        try Data(count: 5_000).write(to: conversion)
        try Data(count: 2_000).write(to: orphanVideo)
        try Data(count: 300).write(to: orphanThumbnail)
        try Data(count: 50).write(to: corruptBackup)
        try LibraryStore(paths: paths).save(library)

        return Setup(
            paths: paths, library: library,
            kept: [videoFile, thumbnail, corruptBackup, paths.libraryFile],
            removable: [conversion, orphanVideo, orphanThumbnail]
        )
    }

    @Test func sizeCountsConversionsAndOrphans() throws {
        let setup = try makeSetup()
        #expect(CacheCleaner(paths: setup.paths).cacheSize(for: setup.library) == 7_300)
    }

    @Test func clearRemovesOnlyCacheAndOrphans() throws {
        let setup = try makeSetup()

        let freed = try CacheCleaner(paths: setup.paths).clear(for: setup.library)

        #expect(freed == 7_300)
        for url in setup.removable {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) should be removed")
        }
        for url in setup.kept {
            #expect(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) should be kept")
        }
    }

    @Test func emptyCacheIsZero() throws {
        let paths = try makeTempPaths()
        let cleaner = CacheCleaner(paths: paths)
        #expect(cleaner.cacheSize(for: .empty) == 0)
        #expect(try cleaner.clear(for: .empty) == 0)
    }

    @Test func sizeIsWrittenInFrench() {
        #expect(DisplayText.size(7_300_000) == "7 Mo")
        #expect(DisplayText.size(0) == "0 Mo")
    }
}
