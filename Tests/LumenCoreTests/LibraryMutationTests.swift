import Foundation
import Testing
@testable import LumenCore

@Suite struct LibraryMutationTests {
    @Test func removeVideoRemovesItFromPlaylists() {
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let first = library.createPlaylist(name: "A")
        let second = library.createPlaylist(name: "B")
        library.addVideo(video.id, toPlaylist: first.id)
        library.addVideo(video.id, toPlaylist: second.id)

        library.removeVideo(id: video.id)

        #expect(library.videos.isEmpty)
        #expect(library.playlists.allSatisfy { $0.videoIDs.isEmpty })
    }

    @Test func removeSelectedVideoClearsSelection() {
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        library.selection = .video(video.id)

        library.removeVideo(id: video.id)

        #expect(library.selection == .none)
    }

    @Test func removeLastVideoOfSelectedPlaylistClearsSelection() {
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let playlist = library.createPlaylist(name: "Soirée")
        library.addVideo(video.id, toPlaylist: playlist.id)
        library.selection = .playlist(playlist.id)

        library.removeVideo(id: video.id)

        #expect(library.selection == .none)
        #expect(library.playlists.map(\.id) == [playlist.id])
    }

    @Test func addVideoToPlaylistIgnoresDuplicates() {
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let playlist = library.createPlaylist(name: "Soirée")

        library.addVideo(video.id, toPlaylist: playlist.id)
        library.addVideo(video.id, toPlaylist: playlist.id)

        #expect(library.playlists[0].videoIDs == [video.id])
    }

    @Test func deleteSelectedPlaylistClearsSelection() {
        var library = Library.empty
        let playlist = library.createPlaylist(name: "Soirée")
        library.selection = .playlist(playlist.id)

        library.deletePlaylist(id: playlist.id)

        #expect(library.playlists.isEmpty)
        #expect(library.selection == .none)
    }

    @Test func moveVideosReorders() {
        var library = Library.empty
        let a = makeVideo(name: "a"), b = makeVideo(name: "b"), c = makeVideo(name: "c")
        let playlist = library.createPlaylist(name: "Soirée")
        for video in [a, b, c] {
            library.addVideo(video)
            library.addVideo(video.id, toPlaylist: playlist.id)
        }

        library.moveVideos(inPlaylist: playlist.id, fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(library.playlists[0].videoIDs == [b.id, c.id, a.id])
    }

    @Test func renameVideoAndPlaylist() {
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let playlist = library.createPlaylist(name: "Soirée")

        library.renameVideo(id: video.id, to: "Mer")
        library.renamePlaylist(id: playlist.id, to: "Nuit")

        #expect(library.video(id: video.id)?.name == "Mer")
        #expect(library.playlists[0].name == "Nuit")
    }
}
