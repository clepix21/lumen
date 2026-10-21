import AppKit
import AVFoundation

/// Plays one video into a host view: looping (single video) or once with an end callback (playlist).
@MainActor
final class WallpaperPlayer {
    var onItemDidEnd: (() -> Void)?

    private let player = AVQueuePlayer()
    private let playerLayer: AVPlayerLayer
    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var wantsPlaying = false
    private var isMuted = false
    private var currentItemObservation: NSKeyValueObservation?

    init(hostView: NSView) {
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostView.wantsLayer = true
        playerLayer.frame = hostView.bounds
        hostView.layer?.addSublayer(playerLayer)

        // The looper swaps items as it loops; each new item must get the mute state.
        currentItemObservation = player.observe(\.currentItem) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.applyAudioState()
            }
        }
    }

    func load(url: URL, loop: Bool) {
        clear()
        let item = AVPlayerItem(url: url)
        if loop {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onItemDidEnd?()
                }
            }
        }
        if wantsPlaying {
            player.play()
        }
    }

    func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        if playing {
            player.play()
        } else {
            player.pause()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player.isMuted = muted
        applyAudioState()
    }

    /// Muting alone still decodes and mixes audio; disabling the audio tracks saves that CPU.
    private func applyAudioState() {
        for item in player.items() {
            for track in item.tracks where track.assetTrack?.mediaType == .audio {
                track.isEnabled = !isMuted
            }
        }
    }

    /// Releases the current item so nothing is decoded.
    func clear() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
