import Foundation
import Testing
@testable import LumenCore

@Suite struct ScreenLayoutTests {
    let main = "MAIN", side = "SIDE", third = "THIRD"
    let a = UUID(), b = UUID()

    @Test func sameVideoEverywhereByDefault() {
        let layout = ScreenLayout()
        #expect(layout.sameOnAllScreens)
        let groups = layout.groups(screens: [main, side], mainSelection: .video(a))
        #expect(groups == [ScreenGroup(selection: .video(a), screenIDs: [main, side])])
    }

    @Test func overridesAreIgnoredWhileSameOnAllScreens() {
        var layout = ScreenLayout()
        layout.overrides[side] = .video(b)
        let groups = layout.groups(screens: [main, side], mainSelection: .video(a))
        #expect(groups == [ScreenGroup(selection: .video(a), screenIDs: [main, side])])
    }

    @Test func screensWithoutOverrideFollowTheMainScreen() {
        var layout = ScreenLayout()
        layout.sameOnAllScreens = false
        let groups = layout.groups(screens: [main, side], mainSelection: .video(a))
        #expect(groups == [ScreenGroup(selection: .video(a), screenIDs: [main, side])])
    }

    @Test func overrideGivesAScreenItsOwnVideo() {
        var layout = ScreenLayout()
        layout.sameOnAllScreens = false
        layout.overrides[side] = .video(b)
        let groups = layout.groups(screens: [main, side], mainSelection: .video(a))
        #expect(groups == [
            ScreenGroup(selection: .video(a), screenIDs: [main]),
            ScreenGroup(selection: .video(b), screenIDs: [side]),
        ])
    }

    @Test func screensShowingTheSameThingShareOneGroup() {
        var layout = ScreenLayout()
        layout.sameOnAllScreens = false
        layout.overrides[side] = .video(b)
        layout.overrides[third] = .video(b)
        let groups = layout.groups(screens: [main, side, third], mainSelection: .video(a))
        #expect(groups.count == 2)
        #expect(groups.last == ScreenGroup(selection: .video(b), screenIDs: [side, third]))
    }

    @Test func overrideOnTheMainScreenIsNotUsed() {
        var layout = ScreenLayout()
        layout.sameOnAllScreens = false
        layout.overrides[main] = .video(b)
        let groups = layout.groups(screens: [main], mainSelection: .video(a))
        #expect(groups == [ScreenGroup(selection: .video(a), screenIDs: [main])])
    }

    @Test func libraryForgetsOverridesOfDeletedVideosAndPlaylists() {
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let playlist = library.createPlaylist(name: "Soirée")
        library.screenLayout.overrides = [side: .video(video.id), third: .playlist(playlist.id)]

        library.removeVideo(id: video.id)
        library.deletePlaylist(id: playlist.id)

        #expect(library.screenLayout.overrides.isEmpty)
    }

    @Test func olderLibrariesGetTheDefaultLayout() throws {
        let json = #"{"videos": [], "settings": {}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(Library.self, from: Data(json.utf8))
        #expect(library.screenLayout == ScreenLayout())
    }
}
