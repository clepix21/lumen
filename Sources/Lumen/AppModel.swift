import AppKit
import LumenCore
import os

private let log = Logger(subsystem: "local.lumen.Lumen", category: "library")

/// The app's state and every user action. Owns playback of the wallpaper.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library: Library
    @Published private(set) var isPlaying = false
    @Published private(set) var currentVideoID: UUID?
    @Published private(set) var session: PlaylistSession?
    @Published var importProgress: Double?
    /// True while files are dragged over the main window.
    @Published var isDropTargeted = false
    /// A newer release found on GitHub, if any.
    @Published private(set) var availableUpdate: UpdateChecker.Release?
    private var updateScheduler: NSBackgroundActivityScheduler?
    @Published var lastError: String?

    /// Called whenever the video shown on the desktop changes (lock screen follows it).
    var onCurrentVideoChange: ((Video?) -> Void)?
    /// Called after any settings change, with the old and new values.
    var onSettingsChange: ((Settings, Settings) -> Void)?
    /// Called when sleep, lock, occlusion or power state changes.
    var onConditionsChange: ((PlaybackConditions) -> Void)?
    /// Called after a video and its files were deleted.
    var onVideoDeleted: ((Video) -> Void)?

    var conditions: PlaybackConditions { monitor.conditions }

    let importer: VideoImporter
    private let store: LibraryStore
    private let screens: WallpaperScreens
    /// Plays the main screen's wallpaper (and every screen showing the same thing).
    private let player: WallpaperPlayer
    private var primaryWindows: [String: WallpaperWindow] = [:]
    /// Players for groups of other screens that show something else (always muted).
    private var channels: [ScreenChannel] = []
    private let monitor: SystemMonitor
    /// Screen the next click in the library applies to; `nil` means the main screen.
    @Published var targetScreenKey: String?
    /// Bumped when screens are plugged in or out, so screen pickers refresh.
    @Published private(set) var screensVersion = 0
    /// Pause asked by the user; the buttons follow it, not automatic energy pauses.
    @Published private(set) var userPaused = false
    /// Unplayable videos skipped in a row; stops a playlist where nothing plays.
    private var consecutiveFailures = 0

    init(paths: LumenPaths, screens: WallpaperScreens) {
        try? paths.createDirectories()
        store = LibraryStore(paths: paths)
        importer = VideoImporter(paths: paths)
        library = store.load()
        self.screens = screens
        // Screens showing the same thing share this player, so the video is decoded once.
        let placeholder = NSView()
        player = WallpaperPlayer(hostView: placeholder)
        player.removeHostView(placeholder)
        monitor = SystemMonitor(windows: screens.windows)
        screens.onChange = { [weak self] _, _ in
            guard let self else { return }
            self.monitor.setWindows(self.screens.windows)
            if let target = self.targetScreenKey, !self.screens.windows.contains(where: { $0.screenKey == target }) {
                self.targetScreenKey = nil
            }
            self.screensVersion += 1
            self.regroupScreens()
        }

        player.setMuted(library.settings.isMuted)
        player.onItemDidEnd = { [weak self] in
            self?.consecutiveFailures = 0
            self?.next()
        }
        player.onItemDidFail = { [weak self] in self?.currentVideoFailed() }
        monitor.onChange = { [weak self] conditions in
            self?.applyPlaybackPolicy()
            self?.onConditionsChange?(conditions)
        }
        // Attach the screens before loading: a player that starts without a visible screen
        // keeps rendering audio even while muted (measured: ~5% CPU instead of 1.4%).
        regroupScreens()
        restoreSelection()
        regroupScreens()
    }

    // MARK: - Screens

    struct ScreenChoice: Identifiable, Equatable {
        let id: String
        let name: String
        let isMain: Bool
    }

    /// Connected screens, main screen first.
    var screenChoices: [ScreenChoice] {
        screens.windows.enumerated().map { ScreenChoice(id: $1.screenKey, name: $1.screenName, isMain: $0 == 0) }
    }

    /// The secondary screen a click applies to, when screens may show different things.
    private var targetSecondaryScreen: String? {
        guard !library.screenLayout.sameOnAllScreens, let target = targetScreenKey,
              target != screens.windows.first?.screenKey,
              screens.windows.contains(where: { $0.screenKey == target }) else { return nil }
        return target
    }

    /// What a screen shows (the main screen shows the library's selection).
    func selection(forScreen key: String?) -> Selection {
        guard let key, key != screens.windows.first?.screenKey, !library.screenLayout.sameOnAllScreens else {
            return library.selection
        }
        return library.screenLayout.overrides[key] ?? library.selection
    }

    func setSameOnAllScreens(_ same: Bool) {
        library.screenLayout.sameOnAllScreens = same
        save()
        regroupScreens()
    }

    /// Assigns screens to the main player or to channels from the library's screen layout.
    private func regroupScreens() {
        let windows = screens.windows
        let byKey = Dictionary(windows.map { ($0.screenKey, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = library.screenLayout.groups(screens: windows.map(\.screenKey), mainSelection: library.selection)

        hostPrimary(on: (groups.first?.screenIDs ?? []).compactMap { byKey[$0] })

        var kept: [ScreenChannel] = []
        for group in groups.dropFirst() {
            let targets = group.screenIDs.compactMap { byKey[$0] }
            if let channel = channels.first(where: { $0.selection == group.selection }) {
                channel.host(targets)
                kept.append(channel)
            } else {
                let channel = ScreenChannel(
                    selection: group.selection,
                    library: { [unowned self] in self.library },
                    fileURL: { [unowned self] in self.importer.fileURL(for: $0) }
                )
                channel.host(targets)
                channel.start()
                kept.append(channel)
            }
        }
        for channel in channels where !kept.contains(where: { $0 === channel }) {
            channel.stop()
        }
        channels = kept
        applyPlaybackPolicy()
    }

    private func hostPrimary(on windows: [WallpaperWindow]) {
        let wanted = Dictionary(windows.map { ($0.screenKey, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, window) in primaryWindows where wanted[key] == nil {
            player.removeHostView(window.playerView)
        }
        for (key, window) in wanted where primaryWindows[key] == nil {
            player.addHostView(window.playerView)
        }
        primaryWindows = wanted
        updatePrimaryVisibility()
    }

    private func updatePrimaryVisibility() {
        for window in primaryWindows.values {
            if currentVideoID != nil {
                window.orderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Derived state

    var currentVideo: Video? {
        currentVideoID.flatMap { library.video(id: $0) }
    }

    var currentPlaylist: Playlist? {
        session.flatMap { library.playlist(id: $0.playlistID) }
    }

    var positionText: String? {
        guard let playlist = currentPlaylist, let session else { return nil }
        return DisplayText.playlistPosition(name: playlist.name, position: session.cursor.position, count: session.count)
    }

    var isInPlaylist: Bool { session != nil }

    func thumbnailURL(for videoID: UUID) -> URL {
        importer.thumbnailURL(for: videoID)
    }

    // MARK: - Playback actions

    func play(videoID: UUID) {
        guard library.video(id: videoID) != nil else { return }
        if let screen = targetSecondaryScreen {
            library.screenLayout.overrides[screen] = .video(videoID)
            save()
            regroupScreens()
            return
        }
        library.selection = .video(videoID)
        session = nil
        userPaused = false
        save()
        show(videoID: videoID, loop: true)
        regroupScreens()
    }

    func play(playlistID: UUID) {
        guard let playlist = library.playlist(id: playlistID), !playlist.videoIDs.isEmpty else { return }
        if let screen = targetSecondaryScreen {
            library.screenLayout.overrides[screen] = .playlist(playlistID)
            save()
            regroupScreens()
            return
        }
        library.selection = .playlist(playlistID)
        userPaused = false
        save()
        session = PlaylistSession(playlist: playlist, shuffle: library.settings.shuffle, seed: Self.seed())
        showSessionVideo()
        regroupScreens()
    }

    func next() {
        guard session != nil else { return }
        session?.advance()
        showSessionVideo()
    }

    func previous() {
        guard session != nil else { return }
        session?.goBack()
        showSessionVideo()
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
                log.error("Import failed for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
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
        onVideoDeleted?(video)

        if session != nil {
            syncSessionWithLibrary()
        } else if wasCurrent {
            stopWallpaper()
        }
        regroupScreens()
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
        let wasCurrent = session?.playlistID == id
        library.deletePlaylist(id: id)
        save()
        if wasCurrent {
            stopWallpaper()
        }
        regroupScreens()
    }

    func addVideo(_ videoID: UUID, toPlaylist playlistID: UUID) {
        library.addVideo(videoID, toPlaylist: playlistID)
        save()
        syncSessionWithLibrary()
    }

    func removeVideo(_ videoID: UUID, fromPlaylist playlistID: UUID) {
        library.removeVideo(videoID, fromPlaylist: playlistID)
        if library.selection == .playlist(playlistID), library.playlist(id: playlistID)?.videoIDs.isEmpty == true {
            library.selection = .none
        }
        save()
        syncSessionWithLibrary()
    }

    func moveVideos(inPlaylist playlistID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        library.moveVideos(inPlaylist: playlistID, fromOffsets: source, toOffset: destination)
        save()
        syncSessionWithLibrary()
    }

    // MARK: - Updates

    /// Checks now, then about once a day at a moment macOS picks to save energy.
    func startUpdateChecks() {
        updateScheduler?.invalidate()
        updateScheduler = nil
        guard library.settings.checkForUpdates else {
            availableUpdate = nil
            return
        }
        Task { await checkForUpdates() }
        let scheduler = NSBackgroundActivityScheduler(identifier: "local.lumen.Lumen.update-check")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.checkForUpdates()
                completion(.finished)
            }
        }
        updateScheduler = scheduler
    }

    func checkForUpdates() async {
        guard library.settings.checkForUpdates else { return }
        availableUpdate = await UpdateChecker().newerRelease(than: Self.appVersion)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Cache

    /// Space `clearCache()` would free: lock screen conversions and orphan files.
    func cacheSize() -> Int64 {
        CacheCleaner(paths: importer.paths).cacheSize(for: library)
    }

    func clearCache() {
        do {
            let freed = try CacheCleaner(paths: importer.paths).clear(for: library)
            lastError = "\(DisplayText.size(freed)) libérés."
        } catch {
            lastError = "Le cache n'a pas pu être entièrement vidé."
        }
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
        if new.shuffle != old.shuffle {
            syncSessionWithLibrary()
        }
        if new.checkForUpdates != old.checkForUpdates {
            startUpdateChecks()
        }
        applyPlaybackPolicy()
        onSettingsChange?(old, new)
    }

    // MARK: - Private

    private static func seed() -> UInt64 {
        UInt64.random(in: .min ... .max)
    }

    private func restoreSelection() {
        switch library.selection {
        case .none:
            stopWallpaper()
        case .video(let id):
            if library.video(id: id) != nil {
                show(videoID: id, loop: true)
            } else {
                library.selection = .none
                save()
                stopWallpaper()
            }
        case .playlist(let id):
            if let playlist = library.playlist(id: id), !playlist.videoIDs.isEmpty {
                session = PlaylistSession(playlist: playlist, shuffle: library.settings.shuffle, seed: Self.seed())
                showSessionVideo()
            } else {
                stopWallpaper()
            }
        }
    }

    /// Re-applies the running playlist after it (or the library) changed. Edits of other
    /// playlists leave the session untouched.
    private func syncSessionWithLibrary() {
        guard var session else { return }
        guard let playlist = library.playlist(id: session.playlistID) else {
            stopWallpaper()
            return
        }
        let change = session.update(playlist: playlist, shuffle: library.settings.shuffle, seed: Self.seed())
        self.session = session
        if change == .reload {
            showSessionVideo()
        }
    }

    /// Skips an unplayable video in a playlist; otherwise stops instead of leaving a black desktop.
    private func currentVideoFailed() {
        let name = currentVideo?.name ?? "La vidéo"
        consecutiveFailures += 1
        if let session, consecutiveFailures < session.count {
            next()
            return
        }
        consecutiveFailures = 0
        library.selection = .none
        save()
        stopWallpaper()
        lastError = "« \(name) » ne peut pas être lue. Supprime-la et importe-la à nouveau."
    }

    private func showSessionVideo() {
        guard let session, let id = session.current else {
            library.selection = .none
            save()
            stopWallpaper()
            return
        }
        show(videoID: id, loop: session.shouldLoop)
    }

    private func show(videoID: UUID, loop: Bool) {
        guard let video = library.video(id: videoID) else {
            stopWallpaper()
            return
        }
        currentVideoID = videoID
        updatePrimaryVisibility()
        player.load(url: importer.fileURL(for: video), loop: loop)
        applyPlaybackPolicy()
        onCurrentVideoChange?(video)
    }

    private func stopWallpaper() {
        session = nil
        currentVideoID = nil
        player.clear()
        player.setPlaying(false)
        updatePrimaryVisibility()
        isPlaying = false
        onCurrentVideoChange?(nil)
    }

    private func applyPlaybackPolicy() {
        var conditions = monitor.conditions
        conditions.userPaused = userPaused
        let allowed = PlaybackPolicy.shouldPlay(conditions, settings: library.settings)
        let play = currentVideoID != nil && allowed
        player.setPlaying(play)
        for channel in channels {
            channel.setPlaying(allowed)
        }
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
