import Foundation
import Testing
@testable import LumenCore

@Suite struct PlaylistSessionTests {
    let a = UUID(), b = UUID(), c = UUID()

    func playlist(_ ids: [UUID], id: UUID = UUID()) -> Playlist {
        Playlist(id: id, name: "Soirée", videoIDs: ids)
    }

    @Test func singleVideoPlaylistLoops() {
        let session = PlaylistSession(playlist: playlist([a]), shuffle: false, seed: 1)
        #expect(session.current == a)
        #expect(session.shouldLoop)
    }

    @Test func otherPlaylistChangesAreIgnored() {
        let own = playlist([a, b, c])
        var session = PlaylistSession(playlist: own, shuffle: false, seed: 1)
        session.advance()

        let change = session.update(playlist: playlist([a, c]), shuffle: false, seed: 2)

        #expect(change == .unchanged)
        #expect(session.current == b)
        #expect(session.count == 3)
    }

    @Test func addingSecondVideoToSingleVideoPlaylistRequiresReload() {
        let id = UUID()
        var session = PlaylistSession(playlist: playlist([a], id: id), shuffle: false, seed: 1)

        let change = session.update(playlist: playlist([a, b], id: id), shuffle: false, seed: 2)

        #expect(change == .reload)
        #expect(session.current == a)
        #expect(!session.shouldLoop)
    }

    @Test func addingToMultiVideoPlaylistKeepsPlaying() {
        let id = UUID()
        var session = PlaylistSession(playlist: playlist([a, b], id: id), shuffle: false, seed: 1)
        session.advance()

        let change = session.update(playlist: playlist([a, b, c], id: id), shuffle: false, seed: 2)

        #expect(change == .unchanged)
        #expect(session.current == b)
        session.advance()
        #expect(session.current == c)
    }

    @Test func removingCurrentMovesToFollowingAndReloads() {
        let id = UUID()
        var session = PlaylistSession(playlist: playlist([a, b, c], id: id), shuffle: false, seed: 1)
        session.advance()

        let change = session.update(playlist: playlist([a, c], id: id), shuffle: false, seed: 2)

        #expect(change == .reload)
        #expect(session.current == c)
    }

    @Test func removingOtherVideoKeepsCurrent() {
        let id = UUID()
        var session = PlaylistSession(playlist: playlist([a, b, c], id: id), shuffle: false, seed: 1)
        session.advance()

        let change = session.update(playlist: playlist([b, c], id: id), shuffle: false, seed: 2)

        #expect(change == .unchanged)
        #expect(session.current == b)
    }

    @Test func goingDownToOneVideoRequiresReloadToLoop() {
        let id = UUID()
        var session = PlaylistSession(playlist: playlist([a, b], id: id), shuffle: false, seed: 1)

        let change = session.update(playlist: playlist([a], id: id), shuffle: false, seed: 2)

        #expect(change == .reload)
        #expect(session.shouldLoop)
    }

    @Test func emptiedPlaylistHasNoCurrent() {
        let id = UUID()
        var session = PlaylistSession(playlist: playlist([a], id: id), shuffle: false, seed: 1)

        let change = session.update(playlist: playlist([], id: id), shuffle: false, seed: 2)

        #expect(change == .reload)
        #expect(session.current == nil)
    }
}
