import Foundation

/// Registers a single "Lumen" video among macOS's Aerial wallpapers so the lock screen can play it.
///
/// There is no public API for this. Findings (macOS 26/27, verified against the real manifest on
/// macOS 27.0.1 and LivePaper's MIT-licensed `AerialsInjector.swift`):
/// - `aerials/manifest/entries.json` has top-level `assets`, `categories`, `initialAssetCount`,
///   `localizationVersion`, `version`; videos live at `aerials/videos/<asset id>.mov`.
/// - A custom asset needs its own category with one subcategory; every subcategory field
///   (`id`, `localizedNameKey`, `localizedDescriptionKey`, `preferredOrder`, `previewImage`,
///   `representativeAssetID`) is required by the system's decoder.
/// - The asset points at its video with `url-4K-SDR-240FPS` (a file URL) and needs `previewImage`.
/// - The system re-reads a swapped video file only after `WallpaperAgent` restarts.
///
/// Only Lumen's own entries are ever touched; everything else in the manifest is preserved.
public struct AerialManifestEditor: Sendable {
    public static let lumenAssetID = "4C554D45-4E00-4000-8000-000000000001"
    public static let lumenCategoryID = "4C554D45-4E00-4000-8000-0000000000C1"
    static let lumenSubcategoryID = "4C554D45-4E00-4000-8000-0000000000C2"

    public let aerialsRoot: URL

    public init(aerialsRoot: URL) {
        self.aerialsRoot = aerialsRoot
    }

    /// `~/Library/Application Support/com.apple.wallpaper/aerials`
    public static func standard() -> AerialManifestEditor {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AerialManifestEditor(aerialsRoot: support.appendingPathComponent("com.apple.wallpaper/aerials", isDirectory: true))
    }

    public var manifestURL: URL { aerialsRoot.appendingPathComponent("manifest/entries.json") }
    public var backupURL: URL { aerialsRoot.appendingPathComponent("manifest/entries.lumen-backup.json") }
    public var slotURL: URL { aerialsRoot.appendingPathComponent("videos/\(Self.lumenAssetID).mov") }
    public var previewURL: URL { aerialsRoot.appendingPathComponent("thumbnails/\(Self.lumenAssetID).jpg") }

    public func isInstalled() throws -> Bool {
        try readManifest().assets.contains { $0["id"] as? String == Self.lumenAssetID }
    }

    /// Adds (or refreshes) the Lumen category and asset. Backs up the original manifest once.
    public func install(previewImageURL: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: manifestURL, to: backupURL)
        }
        try fileManager.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: slotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: previewURL.path) {
            try fileManager.removeItem(at: previewURL)
        }
        try fileManager.copyItem(at: previewImageURL, to: previewURL)

        var manifest = try readManifest()
        manifest.removeLumenEntries()
        let preview = previewURL.absoluteString
        manifest.categories.append([
            "id": Self.lumenCategoryID,
            "localizedNameKey": "Lumen",
            "localizedDescriptionKey": "Lumen",
            "preferredOrder": 999,
            "previewImage": preview,
            "representativeAssetID": Self.lumenAssetID,
            "subcategories": [[
                "id": Self.lumenSubcategoryID,
                "localizedNameKey": "Lumen",
                "localizedDescriptionKey": "Lumen",
                "preferredOrder": 0,
                "previewImage": preview,
                "representativeAssetID": Self.lumenAssetID,
            ]],
        ])
        manifest.assets.append([
            "id": Self.lumenAssetID,
            "localizedNameKey": "Lumen",
            "accessibilityLabel": "Lumen",
            "shotID": "LUMEN",
            "showInTopLevel": true,
            "includeInShuffle": false,
            "preferredOrder": 0,
            "categories": [Self.lumenCategoryID],
            "subcategories": [Self.lumenSubcategoryID],
            "url-4K-SDR-240FPS": slotURL.absoluteString,
            "previewImage": preview,
            "pointsOfInterest": [String: String](),
        ])
        try write(manifest)
    }

    /// Whether the slot is already `source` itself (same file on disk, as left by a hard link).
    public func slotHolds(_ source: URL) -> Bool {
        let fileManager = FileManager.default
        guard let slot = try? fileManager.attributesOfItem(atPath: slotURL.path),
              let file = try? fileManager.attributesOfItem(atPath: source.path) else { return false }
        return (slot[.systemFileNumber] as? NSNumber) == (file[.systemFileNumber] as? NSNumber)
            && (slot[.systemNumber] as? NSNumber) == (file[.systemNumber] as? NSNumber)
    }

    /// Atomically puts `source` in the slot, hard-linking when possible (no copy of a large video).
    /// Returns `false` when the slot already held it.
    @discardableResult
    public func placeInSlot(_ source: URL) throws -> Bool {
        guard !slotHolds(source) else { return false }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: slotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = slotURL.deletingLastPathComponent().appendingPathComponent(".lumen-staging.mov")
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.linkItem(at: source, to: staging)
        } catch {
            try fileManager.copyItem(at: source, to: staging)
        }
        if fileManager.fileExists(atPath: slotURL.path) {
            _ = try fileManager.replaceItemAt(slotURL, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: slotURL)
        }
        return true
    }

    /// Removes only Lumen's entries, video slot and preview. The backup is kept as a safety net.
    public func uninstall() throws {
        var manifest = try readManifest()
        if manifest.removeLumenEntries() {
            try write(manifest)
        }
        let fileManager = FileManager.default
        for url in [slotURL, previewURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - JSON

    private struct Manifest {
        var root: [String: Any]
        var assets: [[String: Any]]
        var categories: [[String: Any]]

        /// Returns whether anything was removed.
        @discardableResult
        mutating func removeLumenEntries() -> Bool {
            let before = assets.count + categories.count
            assets.removeAll { $0["id"] as? String == AerialManifestEditor.lumenAssetID }
            categories.removeAll { $0["id"] as? String == AerialManifestEditor.lumenCategoryID }
            return assets.count + categories.count != before
        }
    }

    private func readManifest() throws -> Manifest {
        let data = try Data(contentsOf: manifestURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Manifest(
            root: root,
            assets: root["assets"] as? [[String: Any]] ?? [],
            categories: root["categories"] as? [[String: Any]] ?? []
        )
    }

    private func write(_ manifest: Manifest) throws {
        var root = manifest.root
        root["assets"] = manifest.assets
        root["categories"] = manifest.categories
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: manifestURL, options: .atomic)
    }
}
