import AVFoundation
import Foundation
import Testing
@testable import LumenCore

@Suite struct HEVCConverterTests {
    @Test func convertsH264ToHEVC() async throws {
        let paths = try makeTempPaths()
        let source = paths.root.appendingPathComponent("clip.mp4")
        try await TestVideoFactory.make(at: source, width: 256, height: 144)
        let destination = paths.lockScreen.appendingPathComponent("clip.mov")

        try await HEVCConverter.convert(source, to: destination)

        let track = try #require(try await AVURLAsset(url: destination).loadTracks(withMediaType: .video).first)
        let formats = try await track.load(.formatDescriptions)
        #expect(formats.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC })
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.lockScreen.path)
        #expect(leftovers == ["clip.mov"])
    }

    @Test func failedConversionLeavesNothing() async throws {
        let paths = try makeTempPaths()
        let source = paths.root.appendingPathComponent("fake.mp4")
        try Data("not a video".utf8).write(to: source)

        await #expect(throws: (any Error).self) {
            try await HEVCConverter.convert(source, to: paths.lockScreen.appendingPathComponent("fake.mov"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.lockScreen.path).isEmpty)
    }
}
