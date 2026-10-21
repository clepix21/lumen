import AppKit
import LumenCore

/// Plays what one group of secondary screens shows (a video or a playlist), always muted so
/// only the main screen makes sound. The main screen is handled by `AppModel` itself.
@MainActor
final class ScreenChannel {
    let selection: Selection
    private(set) var currentVideoID: UUID?
    private var player: WallpaperPlayer?
    private var session: PlaylistSession?
    private var hosted: [String: WallpaperWindow] = [:]
    private var failures = 0
    private let library: () -> Library
    private let fileURL: (Video) -> URL

    init(selection: Selection, library: @escaping () -> Library, fileURL: @escaping (Video) -> URL) {
        self.selection = selection
        self.library = library
        self.fileURL = fileURL
    }

    /// Shows this channel on exactly `windows`.
    func host(_ windows: [WallpaperWindow]) {
        let wanted = Dictionary(windows.map { ($0.screenKey, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, window) in hosted where wanted[key] == nil {
            player?.removeHostView(window.playerView)
            window.orderOut(nil)
        }
        for (key, window) in wanted where hosted[key] == nil {
            if let player {
                player.addHostView(window.playerView)
            } else {
                makePlayer(hostView: window.playerView)
            }
        }
        hosted = wanted
        updateVisibility()
    }

    func start() {
        let library = library()
        switch selection {
        case .none:
            currentVideoID = nil
        case .video(let id):
            show(videoID: id, loop: true)
        case .playlist(let id):
            guard let playlist = library.playlist(id: id), !playlist.videoIDs.isEmpty else { return }
            session = PlaylistSession(playlist: playlist, shuffle: library.settings.shuffle, seed: .random(in: .min ... .max))
            showSessionVideo()
        }
    }

    func setPlaying(_ playing: Bool) {
        player?.setPlaying(playing && currentVideoID != nil)
    }

    func stop() {
        for window in hosted.values {
            player?.removeHostView(window.playerView)
            window.orderOut(nil)
        }
        hosted = [:]
        player?.clear()
        player = nil
        currentVideoID = nil
    }

    private func makePlayer(hostView: NSView) {
        let player = WallpaperPlayer(hostView: hostView)
        player.setMuted(true)
        player.onItemDidEnd = { [weak self] in
            self?.failures = 0
            self?.session?.advance()
            self?.showSessionVideo()
        }
        player.onItemDidFail = { [weak self] in
            guard let self else { return }
            self.failures += 1
            if let session = self.session, self.failures < session.count {
                self.session?.advance()
                self.showSessionVideo()
            } else {
                self.player?.clear()
                self.currentVideoID = nil
                self.updateVisibility()
            }
        }
        self.player = player
    }

    private func showSessionVideo() {
        guard let session, let id = session.current else { return }
        show(videoID: id, loop: session.shouldLoop)
    }

    private func show(videoID: UUID, loop: Bool) {
        guard let video = library().video(id: videoID) else { return }
        currentVideoID = videoID
        player?.load(url: fileURL(video), loop: loop)
        updateVisibility()
    }

    private func updateVisibility() {
        for window in hosted.values {
            if currentVideoID != nil {
                window.orderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }
    }
}
