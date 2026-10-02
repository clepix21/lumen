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
