import Foundation
import Testing
@testable import LumenCore

func makeTempPaths() throws -> LumenPaths {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LumenTests-\(UUID().uuidString)", isDirectory: true)
    let paths = LumenPaths(root: root)
    try paths.createDirectories()
    return paths
}

func makeVideo(name: String = "Plage") -> Video {
    Video(
        id: UUID(), name: name, fileName: "\(UUID().uuidString).mp4",
        duration: 12.5, width: 3840, height: 2160, byteSize: 1_000_000,
        isHEVC: false, importedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

@Suite struct LibraryStoreTests {
    @Test func loadReturnsEmptyWhenFileMissing() throws {
        let store = LibraryStore(paths: try makeTempPaths())
        #expect(store.load() == .empty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = LibraryStore(paths: try makeTempPaths())
        var library = Library.empty
        let video = makeVideo()
        library.addVideo(video)
        let playlist = library.createPlaylist(name: "Soirée")
        library.addVideo(video.id, toPlaylist: playlist.id)
        library.selection = .playlist(playlist.id)
        library.settings.isMuted = false

        try store.save(library)

        #expect(store.load() == library)
    }

    @Test func corruptFileIsSetAsideAndEmptyReturned() throws {
        let paths = try makeTempPaths()
        try Data("{not json".utf8).write(to: paths.libraryFile)
        let store = LibraryStore(paths: paths)

        #expect(store.load() == .empty)

        let names = try FileManager.default.contentsOfDirectory(atPath: paths.root.path)
        #expect(!names.contains("library.json"))
        let corrupt = names.filter { $0.hasPrefix("library.corrupt-") && $0.hasSuffix(".json") }
        #expect(corrupt.count == 1)
    }

    @Test func unreadableFileIsKeptAndNeverOverwritten() throws {
        let paths = try makeTempPaths()
        let store = LibraryStore(paths: paths)
        var library = Library.empty
        library.addVideo(makeVideo())
        try store.save(library)
        let original = try Data(contentsOf: paths.libraryFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: paths.libraryFile.path)

        #expect(store.load() == .empty)
        try store.save(.empty)

        let names = try FileManager.default.contentsOfDirectory(atPath: paths.root.path)
        let aside = try #require(names.first { $0.hasPrefix("library.unreadable-") })
        let asideURL = paths.root.appendingPathComponent(aside)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: asideURL.path)
        #expect(try Data(contentsOf: asideURL) == original)
    }

    @Test func libraryWithMissingKeysKeepsItsDataAndUsesDefaults() throws {
        let paths = try makeTempPaths()
        let id = UUID()
        let json = """
        {
          "videos": [{
            "id": "\(id.uuidString)", "name": "Plage", "fileName": "a.mp4", "duration": 10,
            "width": 1920, "height": 1080, "byteSize": 100, "isHEVC": false,
            "importedAt": "2026-10-21T10:00:00Z"
          }],
          "settings": { "isMuted": false }
        }
        """
        try Data(json.utf8).write(to: paths.libraryFile)

        let library = LibraryStore(paths: paths).load()

        #expect(library.videos.map(\.id) == [id])
        #expect(library.playlists.isEmpty)
        #expect(library.selection == .none)
        #expect(library.settings.isMuted == false)
        #expect(library.settings.launchAtLogin == true)
        #expect(library.settings.pauseWhenOccluded == true)
        #expect(FileManager.default.fileExists(atPath: paths.libraryFile.path))
    }

    @Test func globalShortcutsAreOnByDefaultAndForOlderLibraries() throws {
        #expect(Settings().globalShortcuts == true)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"isMuted": true}"#.utf8))
        #expect(old.globalShortcuts == true)
    }

    @Test func defaultSettingsMatchSpec() {
        let settings = Settings()
        #expect(settings.isMuted == true)
        #expect(settings.launchAtLogin == true)
        #expect(settings.pauseWhenOccluded == true)
        #expect(settings.pauseOnBattery == false)
        #expect(settings.shuffle == false)
        #expect(settings.lockScreenEnabled == false)
    }
}
