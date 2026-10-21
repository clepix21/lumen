import AppKit
import AVFoundation
import Foundation
import Testing
@testable import LumenCore

@MainActor
@Suite struct WallpaperPlayerTests {
    /// Polls (test-only) until `condition` holds or the timeout passes.
    func waitUntil(seconds: Double = 8, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @Test func truncatedVideoReportsFailure() async throws {
        let paths = try makeTempPaths()
        let full = paths.root.appendingPathComponent("full.mp4")
        try await TestVideoFactory.make(at: full, seconds: 2, width: 128, height: 96)
        let data = try Data(contentsOf: full)
        let broken = paths.root.appendingPathComponent("broken.mp4")
        try data.prefix(data.count / 3).write(to: broken)

        let player = WallpaperPlayer(hostView: NSView(frame: NSRect(x: 0, y: 0, width: 128, height: 96)))
        var failed = false
        player.onItemDidFail = { failed = true }
        player.setPlaying(true)
        player.load(url: broken, loop: false)

        #expect(await waitUntil { failed })
    }

    @Test func loopedTruncatedVideoReportsFailure() async throws {
        let paths = try makeTempPaths()
        let broken = paths.root.appendingPathComponent("broken.mp4")
        try Data("not really a video".utf8).write(to: broken)

        let player = WallpaperPlayer(hostView: NSView())
        var failed = false
        player.onItemDidFail = { failed = true }
        player.setPlaying(true)
        player.load(url: broken, loop: true)

        #expect(await waitUntil { failed })
    }

    @Test func mutedPlaylistItemHasAudioDisabled() async throws {
        let paths = try makeTempPaths()
        let clip = paths.root.appendingPathComponent("sound.mp4")
        try await TestVideoFactory.make(at: clip, seconds: 2, width: 128, height: 96, withAudio: true)

        let player = WallpaperPlayer(hostView: NSView())
        player.setMuted(true)
        player.setPlaying(true)
        player.load(url: clip, loop: false)

        #expect(await waitUntil { player.audioTracksEnabled == [false] })
    }

    @Test func extraScreensShareTheSinglePlayer() {
        let first = NSView(), second = NSView()
        let player = WallpaperPlayer(hostView: first)

        player.addHostView(second)

        #expect(player.hostLayers.count == 2)
        #expect(Set(player.hostLayers.compactMap { $0.player.map(ObjectIdentifier.init) }).count == 1)
        #expect(second.layer?.sublayers?.contains { $0 === player.hostLayers.last } == true)
    }

    @Test func addingTheSameViewTwiceIsIgnored() {
        let view = NSView()
        let player = WallpaperPlayer(hostView: view)
        player.addHostView(view)
        #expect(player.hostLayers.count == 1)
    }

    @Test func removedScreenLosesItsLayer() {
        let first = NSView(), second = NSView()
        let player = WallpaperPlayer(hostView: first)
        player.addHostView(second)

        player.removeHostView(second)

        #expect(player.hostLayers.count == 1)
        #expect(second.layer?.sublayers?.isEmpty ?? true)
    }

    @Test func unmutingReenablesAudio() async throws {
        let paths = try makeTempPaths()
        let clip = paths.root.appendingPathComponent("sound.mp4")
        try await TestVideoFactory.make(at: clip, seconds: 2, width: 128, height: 96, withAudio: true)

        let player = WallpaperPlayer(hostView: NSView())
        player.setMuted(true)
        player.load(url: clip, loop: true)
        #expect(await waitUntil { player.audioTracksEnabled == [false] })

        player.setMuted(false)

        #expect(player.audioTracksEnabled == [true])
    }
}
