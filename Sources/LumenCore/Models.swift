import Foundation

/// A video copied into Lumen's storage.
public struct Video: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// File name inside `LumenPaths.videos`.
    public var fileName: String
    public var duration: Double
    public var width: Int
    public var height: Int
    public var byteSize: Int64
    public var isHEVC: Bool
    public var importedAt: Date

    public init(
        id: UUID, name: String, fileName: String, duration: Double,
        width: Int, height: Int, byteSize: Int64, isHEVC: Bool, importedAt: Date
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.duration = duration
        self.width = width
        self.height = height
        self.byteSize = byteSize
        self.isHEVC = isHEVC
        self.importedAt = importedAt
    }
}

public struct Playlist: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var videoIDs: [UUID]

    public init(id: UUID = UUID(), name: String, videoIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.videoIDs = videoIDs
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var isMuted = true
    public var launchAtLogin = true
    public var pauseWhenOccluded = true
    public var pauseOnBattery = false
    public var shuffle = false
    public var lockScreenEnabled = false
    /// Once a day, ask GitHub whether a newer version exists.
    public var checkForUpdates = true

    public init() {}

    /// Missing keys (from an older version) fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? defaults.isMuted
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        pauseWhenOccluded = try container.decodeIfPresent(Bool.self, forKey: .pauseWhenOccluded) ?? defaults.pauseWhenOccluded
        pauseOnBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? defaults.pauseOnBattery
        shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? defaults.shuffle
        lockScreenEnabled = try container.decodeIfPresent(Bool.self, forKey: .lockScreenEnabled) ?? defaults.lockScreenEnabled
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? defaults.checkForUpdates
    }
}

/// What the wallpaper is currently showing.
public enum Selection: Codable, Equatable, Sendable {
    case none
    case video(UUID)
    case playlist(UUID)
}

public struct Library: Codable, Equatable, Sendable {
    public var videos: [Video]
    public var playlists: [Playlist]
    public var selection: Selection
    public var settings: Settings
    /// What each screen shows when several are connected.
    public var screenLayout = ScreenLayout()

    public static let empty = Library(videos: [], playlists: [], selection: .none, settings: Settings())

    public init(videos: [Video], playlists: [Playlist], selection: Selection, settings: Settings) {
        self.videos = videos
        self.playlists = playlists
        self.selection = selection
        self.settings = settings
    }

    /// Missing keys (from an older version) fall back to empty values, so videos are never lost.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videos = try container.decodeIfPresent([Video].self, forKey: .videos) ?? []
        playlists = try container.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        selection = try container.decodeIfPresent(Selection.self, forKey: .selection) ?? .none
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        screenLayout = try container.decodeIfPresent(ScreenLayout.self, forKey: .screenLayout) ?? ScreenLayout()
    }

    public func video(id: UUID) -> Video? {
        videos.first { $0.id == id }
    }

    public func playlist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    public mutating func addVideo(_ video: Video) {
        videos.append(video)
    }

    /// Removes a video everywhere; clears the selection if nothing is left to show.
    public mutating func removeVideo(id: UUID) {
        videos.removeAll { $0.id == id }
        screenLayout.forget(videoID: id)
        for index in playlists.indices {
            playlists[index].videoIDs.removeAll { $0 == id }
        }
        switch selection {
        case .video(id):
            selection = .none
        case .playlist(let playlistID) where playlist(id: playlistID)?.videoIDs.isEmpty ?? true:
            selection = .none
        default:
            break
        }
    }

    public mutating func renameVideo(id: UUID, to name: String) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].name = name
    }

    @discardableResult
    public mutating func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        return playlist
    }

    public mutating func renamePlaylist(id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
    }

    public mutating func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        screenLayout.forget(playlistID: id)
        if selection == .playlist(id) {
            selection = .none
        }
    }

    public mutating func addVideo(_ videoID: UUID, toPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].videoIDs.contains(videoID) else { return }
        playlists[index].videoIDs.append(videoID)
    }

    public mutating func removeVideo(_ videoID: UUID, fromPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].videoIDs.removeAll { $0 == videoID }
    }

    public mutating func moveVideos(inPlaylist playlistID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var ids = playlists[index].videoIDs
        let moving = source.map { ids[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for offset in source.reversed() {
            ids.remove(at: offset)
        }
        ids.insert(contentsOf: moving, at: insertAt)
        playlists[index].videoIDs = ids
    }
}
