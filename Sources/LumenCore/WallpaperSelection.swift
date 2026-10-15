import Foundation

/// Reads (never writes) the system's wallpaper choices to know whether an aerial is in use.
///
/// The store is `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`; each
/// choice keeps its settings as a nested binary property list (`Configuration`), which holds
/// an `assetID` for aerial wallpapers.
public enum WallpaperSelection {
    public static let standardStoreURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("com.apple.wallpaper/Store/Index.plist")
    }()

    /// Whether any desktop or lock screen choice in the store points at `assetID`.
    public static func references(assetID: String, inStore data: Data) -> Bool {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return false }
        return contains(assetID, in: root)
    }

    /// Reads the user's store; `false` when it cannot be read.
    public static func isSelected(assetID: String, storeURL: URL = standardStoreURL) -> Bool {
        guard let data = try? Data(contentsOf: storeURL) else { return false }
        return references(assetID: assetID, inStore: data)
    }

    private static func contains(_ assetID: String, in value: Any) -> Bool {
        switch value {
        case let dictionary as [String: Any]:
            if dictionary["assetID"] as? String == assetID { return true }
            return dictionary.values.contains { contains(assetID, in: $0) }
        case let array as [Any]:
            return array.contains { contains(assetID, in: $0) }
        case let data as Data:
            guard let nested = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return false }
            return contains(assetID, in: nested)
        default:
            return false
        }
    }
}
