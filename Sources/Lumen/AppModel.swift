import AppKit
import LumenCore

/// The app's state and every user action. Owns playback of the wallpaper.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library: Library
    @Published private(set) var isPlaying = false
    @Published private(set) var currentVideoID: UUID?
    @Published var importProgress: Double?
    @Published var lastError: String?

    /// Called whenever the video shown on the desktop changes (lock screen follows it).
    var onCurrentVideoChange: ((Video?) -> Void)?
    /// Called after any settings change, with the old and new values.
    var onSettingsChange: ((Settings, Settings) -> Void)?

    let importer: VideoImporter
    private let store: LibraryStore
    private let window: WallpaperWindow
    private let player: WallpaperPlayer
    private let monitor: SystemMonitor
    private var cursor: PlaylistCursor?
    private var userPaused = false

    init(paths: LumenPaths, window: WallpaperWindow) {
        try? paths.createDirectories()
        store = LibraryStore(paths: paths)
        importer = VideoImporter(paths: paths)
        library = store.load()
        self.window = window
        player = WallpaperPlayer(hostView: window.playerView)
        monitor = SystemMonitor(window: window)

        player.setMuted(library.settings.isMuted)
        player.onItemDidEnd = { [weak self] in self?.advance() }
        monitor.onChange = { [weak self] _ in self?.applyPlaybackPolicy() }
        restoreSelection()
    }

    // MARK: - Derived state

    var currentVideo: Video? {
        currentVideoID.flatMap { library.video(id: $0) }
    }

    var currentPlaylist: Playlist? {
        guard case .playlist(let id) = library.selection else { return nil }
        return library.playlist(id: id)
    }

    var positionText: String? {
        guard let playlist = currentPlaylist, let cursor else { return nil }
        return DisplayText.playlistPosition(name: playlist.name, position: cursor.position, count: cursor.count)
    }

    var isInPlaylist: Bool { currentPlaylist != nil }

    func thumbnailURL(for videoID: UUID) -> URL {
        importer.thumbnailURL(for: videoID)
    }

    // MARK: - Playback actions

    func play(videoID: UUID) {
        guard library.video(id: videoID) != nil else { return }
        library.selection = .video(videoID)
        cursor = nil
        userPaused = false
        save()
        show(videoID: videoID, loop: true)
    }

    func play(playlistID: UUID) {
        guard let playlist = library.playlist(id: playlistID), !playlist.videoIDs.isEmpty else { return }
        library.selection = .playlist(playlistID)
        userPaused = false
        save()
        startCursor(for: playlist)
    }

    func next() {
        guard cursor != nil else { return }
        cursor?.next()
        showCursorVideo()
    }

    func previous() {
        guard cursor != nil else { return }
        cursor?.previous()
        showCursorVideo()
    }

    func togglePause() {
        userPaused.toggle()
        applyPlaybackPolicy()
    }

    func toggleMute() {
        update { $0.isMuted.toggle() }
    }

    // MARK: - Library actions

    func importVideos(_ urls: [URL]) async {
        for url in urls {
            importProgress = 0
            do {
                let video = try await importer.importVideo(from: url) { value in
                    Task { @MainActor [weak self] in self?.importProgress = value }
                }
                library.addVideo(video)
                save()
                if library.selection == .none {
                    play(videoID: video.id)
                }
            } catch {
                lastError = (error as? ImportError)?.frenchMessage ?? ImportError.copyFailed.frenchMessage
            }
        }
        importProgress = nil
    }

    func deleteVideo(id: UUID) {
        guard let video = library.video(id: id) else { return }
        let wasCurrent = currentVideoID == id
        library.removeVideo(id: id)
        try? importer.deleteFiles(for: video)
        save()

        guard wasCurrent else {
            cursor?.remove(id)
            return
        }
        if var cursor, library.selection != .none {
            cursor.remove(id)
            self.cursor = cursor
            showCursorVideo()
        } else {
            stopWallpaper()
        }
    }

    func renameVideo(id: UUID, to name: String) {
        library.renameVideo(id: id, to: name)
        save()
    }

    @discardableResult
    func createPlaylist(name: String) -> UUID {
        let playlist = library.createPlaylist(name: name)
        save()
        return playlist.id
    }

    func renamePlaylist(id: UUID, to name: String) {
        library.renamePlaylist(id: id, to: name)
        save()
    }

    func deletePlaylist(id: UUID) {
        let wasCurrent = library.selection == .playlist(id)
        library.deletePlaylist(id: id)
        save()
        if wasCurrent {
            stopWallpaper()
        }
    }

    func addVideo(_ videoID: UUID, toPlaylist playlistID: UUID) {
        library.addVideo(videoID, toPlaylist: playlistID)
        save()
        refreshCursorIfCurrent(playlistID)
    }

    func removeVideo(_ videoID: UUID, fromPlaylist playlistID: UUID) {
        library.removeVideo(videoID, fromPlaylist: playlistID)
        if library.selection == .playlist(playlistID), library.playlist(id: playlistID)?.videoIDs.isEmpty == true {
            library.selection = .none
            save()
            stopWallpaper()
            return
        }
        save()
        if library.selection == .playlist(playlistID), currentVideoID == videoID {
            cursor?.remove(videoID)
            showCursorVideo()
        } else {
            cursor?.remove(videoID)
        }
    }

    func moveVideos(inPlaylist playlistID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        library.moveVideos(inPlaylist: playlistID, fromOffsets: source, toOffset: destination)
        save()
        refreshCursorIfCurrent(playlistID)
    }

    func update(_ change: (inout Settings) -> Void) {
        let old = library.settings
        change(&library.settings)
        let new = library.settings
        guard new != old else { return }
        save()
        if new.isMuted != old.isMuted {
            player.setMuted(new.isMuted)
        }
        if new.shuffle != old.shuffle, let playlist = currentPlaylist {
            refreshCursor(for: playlist)
        }
        applyPlaybackPolicy()
        onSettingsChange?(old, new)
    }

    // MARK: - Private

    private func restoreSelection() {
        switch library.selection {
        case .none:
            stopWallpaper()
        case .video(let id):
            show(videoID: id, loop: true)
        case .playlist(let id):
            if let playlist = library.playlist(id: id) {
                startCursor(for: playlist)
            } else {
                stopWallpaper()
            }
        }
    }

    private func startCursor(for playlist: Playlist) {
        cursor = PlaylistCursor(videoIDs: playlist.videoIDs, shuffle: library.settings.shuffle, seed: UInt64.random(in: .min ... .max))
        showCursorVideo()
    }

    /// Rebuilds the cursor after the playlist changed, keeping the current video playing.
    private func refreshCursorIfCurrent(_ playlistID: UUID) {
        guard library.selection == .playlist(playlistID), let playlist = library.playlist(id: playlistID) else { return }
        refreshCursor(for: playlist)
    }

    private func refreshCursor(for playlist: Playlist) {
        var fresh = PlaylistCursor(videoIDs: playlist.videoIDs, shuffle: library.settings.shuffle, seed: UInt64.random(in: .min ... .max))
        if let currentVideoID, fresh.order.contains(currentVideoID) {
            while fresh.current != currentVideoID { fresh.next() }
        }
        cursor = fresh
    }

    private func advance() {
        cursor?.next()
        showCursorVideo()
    }

    private func showCursorVideo() {
        guard let cursor, let id = cursor.current else {
            library.selection = .none
            save()
            stopWallpaper()
            return
        }
        // A one-video playlist simply loops.
        show(videoID: id, loop: cursor.count == 1)
    }

    private func show(videoID: UUID, loop: Bool) {
        guard let video = library.video(id: videoID) else {
            stopWallpaper()
            return
        }
        currentVideoID = videoID
        window.fitToMainScreen()
        window.orderFront(nil)
        player.load(url: importer.fileURL(for: video), loop: loop)
        applyPlaybackPolicy()
        onCurrentVideoChange?(video)
    }

    private func stopWallpaper() {
        cursor = nil
        currentVideoID = nil
        player.clear()
        player.setPlaying(false)
        window.orderOut(nil)
        isPlaying = false
        onCurrentVideoChange?(nil)
    }

    private func applyPlaybackPolicy() {
        var conditions = monitor.conditions
        conditions.userPaused = userPaused
        let play = currentVideoID != nil && PlaybackPolicy.shouldPlay(conditions, settings: library.settings)
        player.setPlaying(play)
        isPlaying = play
    }

    private func save() {
        do {
            try store.save(library)
        } catch {
            lastError = "Impossible d'enregistrer la bibliothèque."
        }
    }
}
