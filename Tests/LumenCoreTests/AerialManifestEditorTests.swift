import Foundation
import Testing
@testable import LumenCore

@Suite struct AerialManifestEditorTests {
    let fileManager = FileManager.default

    /// A temp `aerials/` folder holding a copy of the fixture manifest and an empty `videos/`.
    func makeAerials() throws -> AerialManifestEditor {
        let root = fileManager.temporaryDirectory.appendingPathComponent("aerials-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("manifest"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("videos"), withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "entries", withExtension: "json", subdirectory: "Fixtures"))
        try fileManager.copyItem(at: fixture, to: root.appendingPathComponent("manifest/entries.json"))
        return AerialManifestEditor(aerialsRoot: root)
    }

    func manifest(_ editor: AerialManifestEditor) throws -> [String: Any] {
        let data = try Data(contentsOf: editor.manifestURL)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func assets(_ editor: AerialManifestEditor) throws -> [NSDictionary] {
        try #require(try manifest(editor)["assets"] as? [NSDictionary])
    }

    func makePreview() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        return url
    }

    @Test func installAddsOneLumenAssetAndKeepsOthers() throws {
        let editor = try makeAerials()
        let original = try assets(editor)

        try editor.install(previewImageURL: try makePreview())

        let after = try assets(editor)
        #expect(after.count == 3)
        #expect(Array(after.prefix(2)) == original)
        #expect(try editor.isInstalled())
        let lumen = try #require(after.last)
        #expect(lumen["id"] as? String == AerialManifestEditor.lumenAssetID)
        #expect(lumen["url-4K-SDR-240FPS"] as? String == editor.slotURL.absoluteString)
    }

    @Test func installAddsLumenCategoryWithCompleteSubcategory() throws {
        let editor = try makeAerials()
        try editor.install(previewImageURL: try makePreview())

        let categories = try #require(try manifest(editor)["categories"] as? [[String: Any]])
        #expect(categories.count == 2)
        let lumen = try #require(categories.first { $0["id"] as? String == AerialManifestEditor.lumenCategoryID })
        let sub = try #require((lumen["subcategories"] as? [[String: Any]])?.first)
        for key in ["id", "localizedNameKey", "localizedDescriptionKey", "preferredOrder", "previewImage", "representativeAssetID"] {
            #expect(sub[key] != nil, "missing \(key)")
        }
    }

    @Test func installIsIdempotent() throws {
        let editor = try makeAerials()
        let preview = try makePreview()
        try editor.install(previewImageURL: preview)
        try editor.install(previewImageURL: preview)
        #expect(try assets(editor).count == 3)
        #expect((try manifest(editor)["categories"] as? [Any])?.count == 2)
    }

    @Test func installBacksUpOnlyOnce() throws {
        let editor = try makeAerials()
        let original = try Data(contentsOf: editor.manifestURL)
        let preview = try makePreview()
        try editor.install(previewImageURL: preview)
        try editor.install(previewImageURL: preview)
        #expect(try Data(contentsOf: editor.backupURL) == original)
    }

    @Test func uninstallRemovesOnlyLumenAssetAndSlot() throws {
        let editor = try makeAerials()
        let original = try assets(editor)
        try editor.install(previewImageURL: try makePreview())
        try Data("video".utf8).write(to: editor.slotURL)

        try editor.uninstall()

        #expect(try assets(editor) == original)
        #expect((try manifest(editor)["categories"] as? [Any])?.count == 1)
        #expect(!fileManager.fileExists(atPath: editor.slotURL.path))
        #expect(!fileManager.fileExists(atPath: editor.previewURL.path))
        #expect(fileManager.fileExists(atPath: editor.backupURL.path))
        #expect(try !editor.isInstalled())
    }

    @Test func uninstallKeepsChangesAppleMadeMeanwhile() throws {
        let editor = try makeAerials()
        try editor.install(previewImageURL: try makePreview())
        var json = try manifest(editor)
        var list = try #require(json["assets"] as? [[String: Any]])
        list.append(["id": "APPLE-NEW", "shotID": "NEW"])
        json["assets"] = list
        try JSONSerialization.data(withJSONObject: json).write(to: editor.manifestURL)

        try editor.uninstall()

        let ids = try assets(editor).compactMap { $0["id"] as? String }
        #expect(ids.contains("APPLE-NEW"))
        #expect(ids.count == 3)
    }

    @Test func uninstallWithoutInstallDoesNothing() throws {
        let editor = try makeAerials()
        let before = try Data(contentsOf: editor.manifestURL)
        try editor.uninstall()
        #expect(try Data(contentsOf: editor.manifestURL) == before)
    }
}
