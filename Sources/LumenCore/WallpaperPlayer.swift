import AppKit
import AVFoundation

/// Plays one video into a host view: looping (single video) or once with an end callback (playlist).
///
/// Looping seeks back to the start instead of using `AVPlayerLooper`, which raises an exception
/// for items without a duration and keeps several replicas decoding.
@MainActor
public final class WallpaperPlayer {
    public var onItemDidEnd: (() -> Void)?
    /// Called when the current video cannot be played (corrupt, truncated or missing file).
    public var onItemDidFail: (() -> Void)?

    private let player = AVPlayer()
    private let playerLayer: AVPlayerLayer
    private var loops = false
    private var wantsPlaying = false
    private var isMuted = false
    private var itemObservers: [NSObjectProtocol] = []
    private var itemObservations: [NSKeyValueObservation] = []

    public init(hostView: NSView) {
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostView.wantsLayer = true
        playerLayer.frame = hostView.bounds
        hostView.layer?.addSublayer(playerLayer)
    }

    /// Whether each audio track of the current item is enabled (empty when it has none).
    public var audioTracksEnabled: [Bool] {
        audioTracks(of: player.currentItem).map(\.isEnabled)
    }

    public func load(url: URL, loop: Bool) {
        clear()
        loops = loop
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        if wantsPlaying {
            player.play()
        }
    }

    public func setPlaying(_ playing: Bool) {
        wantsPlaying = playing
        if playing {
            player.play()
        } else {
            player.pause()
        }
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        player.isMuted = muted
        applyAudioState(to: player.currentItem)
    }

    /// Releases the current item so nothing is decoded.
    public func clear() {
        for observer in itemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemObservers.removeAll()
        itemObservations.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Private

    private func observe(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        itemObservers.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidEnd() }
        })
        itemObservers.append(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onItemDidFail?() }
        })
        // KVO may fire on any thread: hop to the main actor before touching state.
        itemObservations.append(item.observe(\.status) { @Sendable [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.onItemDidFail?()
            }
        })
        // Tracks are only known once the item is ready; muting must reach them then.
        itemObservations.append(item.observe(\.tracks, options: [.initial]) { @Sendable [weak self] item, _ in
            Task { @MainActor in
                self?.applyAudioState(to: item)
            }
        })
    }

    private func itemDidEnd() {
        if loops {
            player.seek(to: .zero)
            if wantsPlaying {
                player.play()
            }
        } else {
            onItemDidEnd?()
        }
    }

    /// Muting alone still decodes and mixes audio; disabling the audio tracks saves that CPU.
    private func applyAudioState(to item: AVPlayerItem?) {
        for track in audioTracks(of: item) {
            track.isEnabled = !isMuted
        }
    }

    private func audioTracks(of item: AVPlayerItem?) -> [AVPlayerItemTrack] {
        item?.tracks.filter { $0.assetTrack?.mediaType == .audio } ?? []
    }
}
