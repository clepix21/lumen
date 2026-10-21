import Foundation

/// The playlist currently on the wallpaper: its cursor, and how edits to that playlist
/// affect what is playing.
public struct PlaylistSession: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        /// The video on screen and its loop mode stay as they are.
        case unchanged
        /// The player must load `current` again (it changed, or the loop mode did).
        case reload
    }

    public let playlistID: UUID
    public private(set) var cursor: PlaylistCursor

    public init(playlist: Playlist, shuffle: Bool, seed: UInt64) {
        playlistID = playlist.id
        cursor = PlaylistCursor(videoIDs: playlist.videoIDs, shuffle: shuffle, seed: seed)
    }

    public var current: UUID? { cursor.current }
    public var count: Int { cursor.count }
    /// A one-video playlist loops its only video.
    public var shouldLoop: Bool { cursor.count == 1 }

    public mutating func advance() { cursor.next() }
    public mutating func goBack() { cursor.previous() }

    /// Applies an edit of this session's playlist; edits of any other playlist are ignored.
    public mutating func update(playlist: Playlist, shuffle: Bool, seed: UInt64) -> Change {
        guard playlist.id == playlistID else { return .unchanged }
        let wasLooping = shouldLoop
        let previous = cursor.current

        // Where to continue: the current video if it is still there, else the one that followed it.
        var target = previous
        if let previous, !playlist.videoIDs.contains(previous) {
            var old = cursor
            while let id = old.current, !playlist.videoIDs.contains(id) {
                old.remove(id)
            }
            target = old.current
        }

        var fresh = PlaylistCursor(videoIDs: playlist.videoIDs, shuffle: shuffle, seed: seed)
        if let target, fresh.order.contains(target) {
            while fresh.current != target { fresh.next() }
        }
        cursor = fresh

        return fresh.current != previous || shouldLoop != wasLooping ? .reload : .unchanged
    }
}
