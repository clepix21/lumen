import AppKit
import LumenCore
import SwiftUI

/// Silent looping preview of a video. The player exists only while this view is on screen,
/// so a thumbnail costs nothing until the pointer rests on it.
struct HoverVideoPreview: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var player: WallpaperPlayer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let player = WallpaperPlayer(hostView: view)
        player.setMuted(true)
        player.setPlaying(true)
        player.load(url: url, loop: true)
        context.coordinator.player = player
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player?.clear()
        coordinator.player = nil
    }
}
