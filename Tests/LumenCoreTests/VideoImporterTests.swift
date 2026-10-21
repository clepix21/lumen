import AVFoundation
import Foundation
import Testing
@testable import LumenCore

@Suite struct VideoImporterTests {
    let fileManager = FileManager.default

    func makeSourceDir() throws -> URL {
        let dir = fileManager.temporaryDirectory.appendingPathComponent("LumenSrc-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func contents(_ url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: url.path)
    }

    @Test func importCopiesFileAndReadsMetadata() async throws {
        let paths = try makeTempPaths()
        let source = try makeSourceDir().appendingPathComponent("Plage.mp4")
        try await TestVideoFactory.make(at: source)
        let importer = VideoImporter(paths: paths)

        let video = try await importer.importVideo(from: source) { _ in }

        #expect(video.name == "Plage")
        #expect(video.width == 64)
        #expect(video.height == 48)
        #expect(abs(video.duration - 1) < 0.1)
        #expect(video.isHEVC == false)
        #expect(video.byteSize > 0)
        let copy = importer.fileURL(for: video)
        #expect(copy.lastPathComponent == "\(video.id.uuidString).mp4")
        #expect(fileManager.fileExists(atPath: copy.path))
        #expect(fileManager.fileExists(atPath: source.path))
    }

    @Test func importDetectsHEVC() async throws {
        let paths = try makeTempPaths()
        let source = try makeSourceDir().appendingPathComponent("Nuit.mov")
        try await TestVideoFactory.make(at: source, width: 128, height: 96, codec: .hevc)

        let video = try await VideoImporter(paths: paths).importVideo(from: source) { _ in }

        #expect(video.isHEVC == true)
    }

    @Test func importWritesThumbnail() async throws {
        let paths = try makeTempPaths()
        let source = try makeSourceDir().appendingPathComponent("Plage.mp4")
        try await TestVideoFactory.make(at: source)
        let importer = VideoImporter(paths: paths)

        let video = try await importer.importVideo(from: source) { _ in }

        let data = try Data(contentsOf: importer.thumbnailURL(for: video.id))
        #expect(Array(data.prefix(3)) == [0xFF, 0xD8, 0xFF])
    }

    @Test func importReportsProgressEndingAtOne() async throws {
        let paths = try makeTempPaths()
        let source = try makeSourceDir().appendingPathComponent("Plage.mp4")
        try await TestVideoFactory.make(at: source)
        let recorder = ProgressRecorder()

        _ = try await VideoImporter(paths: paths).importVideo(from: source) { recorder.record($0) }

        #expect(recorder.values.last == 1.0)
    }

    @Test func rejectsNonVideo() async throws {
        let paths = try makeTempPaths()
        let source = try makeSourceDir().appendingPathComponent("fake.mp4")
        try Data("hello".utf8).write(to: source)

        await #expect(throws: ImportError.notPlayable) {
            _ = try await VideoImporter(paths: paths).importVideo(from: source) { _ in }
        }
        #expect(try contents(paths.videos).isEmpty)
        #expect(try contents(paths.thumbnails).isEmpty)
    }

    @Test func failedCopyLeavesNothing() async throws {
        let paths = try makeTempPaths()
        let missing = try makeSourceDir().appendingPathComponent("missing.mp4")

        await #expect(throws: ImportError.self) {
            _ = try await VideoImporter(paths: paths).importVideo(from: missing) { _ in }
        }
        #expect(try contents(paths.videos).isEmpty)
    }

    @Test func deleteFilesRemovesVideoAndThumbnail() async throws {
        let paths = try makeTempPaths()
        let source = try makeSourceDir().appendingPathComponent("Plage.mp4")
        try await TestVideoFactory.make(at: source)
        let importer = VideoImporter(paths: paths)
        let video = try await importer.importVideo(from: source) { _ in }

        try importer.deleteFiles(for: video)

        #expect(try contents(paths.videos).isEmpty)
        #expect(try contents(paths.thumbnails).isEmpty)
    }

    @Test func frenchMessages() {
        #expect(ImportError.notPlayable.frenchMessage == "Ce fichier n'est pas une vidéo lisible.")
        #expect(ImportError.copyFailed.frenchMessage == "La copie de la vidéo a échoué.")
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func record(_ value: Double) {
        lock.lock(); storage.append(value); lock.unlock()
    }

    var values: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
