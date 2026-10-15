import Foundation
import Testing
@testable import LumenCore

/// Records what the controller asked for, without touching the real system.
@MainActor
final class LockScreenProbe {
    var restarts = 0
    var conversionsStarted = 0
    var conversionsCancelled = 0
    var notices: [String] = []
}

@MainActor
@Suite struct LockScreenControllerTests {
    struct Setup {
        let controller: LockScreenController
        let editor: AerialManifestEditor
        let paths: LumenPaths
        let probe: LockScreenProbe
    }

    func waitUntil(seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func makeSetup(
        delay: Duration = .zero, conversionNeverEnds: Bool = false, conversionTime: UInt64 = 0,
        lumenSelected: Bool = true
    ) throws -> Setup {
        let paths = try makeTempPaths()
        let aerials = paths.root.appendingPathComponent("aerials", isDirectory: true)
        try FileManager.default.createDirectory(at: aerials.appendingPathComponent("manifest"), withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "entries", withExtension: "json", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: aerials.appendingPathComponent("manifest/entries.json"))
        let editor = AerialManifestEditor(aerialsRoot: aerials)
        let probe = LockScreenProbe()
        let controller = LockScreenController(
            editor: editor,
            cache: LockScreenCache(paths: paths),
            importer: VideoImporter(paths: paths),
            convert: { @MainActor source, destination in
                probe.conversionsStarted += 1
                do {
                    if conversionNeverEnds {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                    }
                    if conversionTime > 0 {
                        try await Task.sleep(nanoseconds: conversionTime)
                    }
                    try FileManager.default.copyItem(at: source, to: destination)
                } catch {
                    probe.conversionsCancelled += 1
                    throw error
                }
            },
            restartAgent: { probe.restarts += 1 },
            isLumenSelected: { lumenSelected },
            slotUpdateDelay: delay
        )
        controller.onNotice = { probe.notices.append($0) }
        return Setup(controller: controller, editor: editor, paths: paths, probe: probe)
    }

    /// A stored video with a real file and thumbnail.
    func storedVideo(_ setup: Setup, hevc: Bool = true) throws -> Video {
        var video = makeVideo()
        video.isHEVC = hevc
        let importer = VideoImporter(paths: setup.paths)
        try Data(UUID().uuidString.utf8).write(to: importer.fileURL(for: video))
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: importer.thumbnailURL(for: video.id))
        return video
    }

    @Test func enablingInstallsAndRestartsOnce() async throws {
        let setup = try makeSetup()
        let video = try storedVideo(setup)

        setup.controller.setEnabled(true, current: video)

        #expect(try setup.editor.isInstalled())
        #expect(setup.editor.slotHolds(VideoImporter(paths: setup.paths).fileURL(for: video)))
        #expect(setup.probe.restarts == 1)
    }

    @Test func sameVideoAgainDoesNotRestartAgent() async throws {
        let setup = try makeSetup()
        let video = try storedVideo(setup)
        setup.controller.setEnabled(true, current: video)

        setup.controller.desktopVideoDidChange(video)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(setup.probe.restarts == 1)
    }

    @Test func rapidChangesAreCoalesced() async throws {
        let setup = try makeSetup(delay: .milliseconds(300))
        let first = try storedVideo(setup), second = try storedVideo(setup), third = try storedVideo(setup)
        setup.controller.setEnabled(true, current: first)

        setup.controller.desktopVideoDidChange(second)
        setup.controller.desktopVideoDidChange(third)

        let importer = VideoImporter(paths: setup.paths)
        #expect(await waitUntil { setup.editor.slotHolds(importer.fileURL(for: third)) })
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(setup.probe.restarts == 2)
    }

    @Test func noConversionStartsOnBattery() async throws {
        let setup = try makeSetup()
        var conditions = PlaybackConditions()
        conditions.isOnBattery = true
        setup.controller.conditionsDidChange(conditions)

        setup.controller.setEnabled(true, current: try storedVideo(setup, hevc: false))
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(setup.probe.conversionsStarted == 0)
    }

    @Test func runningConversionIsCancelledOnBattery() async throws {
        let setup = try makeSetup(conversionNeverEnds: true)
        setup.controller.setEnabled(true, current: try storedVideo(setup, hevc: false))
        #expect(await waitUntil { setup.probe.conversionsStarted == 1 })

        var conditions = PlaybackConditions()
        conditions.isOnBattery = true
        setup.controller.conditionsDidChange(conditions)

        #expect(await waitUntil { setup.probe.conversionsCancelled == 1 })
        #expect(setup.probe.notices.isEmpty)
    }

    @Test func conversionResumesOnACPower() async throws {
        let setup = try makeSetup()
        var conditions = PlaybackConditions()
        conditions.isOnBattery = true
        setup.controller.conditionsDidChange(conditions)
        let video = try storedVideo(setup, hevc: false)
        setup.controller.setEnabled(true, current: video)

        conditions.isOnBattery = false
        setup.controller.conditionsDidChange(conditions)

        let cached = LockScreenCache(paths: setup.paths).cachedURL(for: video)
        #expect(await waitUntil { setup.editor.slotHolds(cached) })
    }

    @Test func videoDeletedDuringConversionLeavesNoCache() async throws {
        let setup = try makeSetup(conversionTime: 300_000_000)
        let video = try storedVideo(setup, hevc: false)
        setup.controller.setEnabled(true, current: video)
        #expect(await waitUntil { setup.probe.conversionsStarted == 1 })

        setup.controller.videoWasDeleted(video)
        try await Task.sleep(nanoseconds: 600_000_000)

        let cached = LockScreenCache(paths: setup.paths).cachedURL(for: video)
        #expect(!FileManager.default.fileExists(atPath: cached.path))
    }

    @Test func slotChangeDoesNotRestartAgentWhenLumenIsNotSelected() async throws {
        let setup = try makeSetup(lumenSelected: false)
        let first = try storedVideo(setup), second = try storedVideo(setup)
        setup.controller.setEnabled(true, current: first)
        #expect(setup.probe.restarts == 1)

        setup.controller.desktopVideoDidChange(second)

        let importer = VideoImporter(paths: setup.paths)
        #expect(await waitUntil { setup.editor.slotHolds(importer.fileURL(for: second)) })
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(setup.probe.restarts == 1)
    }

    @Test func disablingUninstalls() async throws {
        let setup = try makeSetup()
        setup.controller.setEnabled(true, current: try storedVideo(setup))

        setup.controller.setEnabled(false, current: nil)

        #expect(try !setup.editor.isInstalled())
        #expect(setup.probe.restarts == 2)
    }
}
