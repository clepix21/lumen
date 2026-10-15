import Foundation
import Testing
@testable import LumenCore

@Suite struct WallpaperSelectionTests {
    /// Builds a store shaped like `com.apple.wallpaper/Store/Index.plist`, where each choice's
    /// `Configuration` is itself a binary property list.
    func storeData(desktopAssetID: String?, idleAssetID: String?) throws -> Data {
        func choice(_ assetID: String?) throws -> [String: Any] {
            if let assetID {
                let config = try PropertyListSerialization.data(
                    fromPropertyList: ["assetID": assetID], format: .binary, options: 0)
                return ["Provider": "com.apple.wallpaper.choice.aerials", "Files": [], "Configuration": config]
            }
            let config = try PropertyListSerialization.data(
                fromPropertyList: ["type": "imageFile", "url": ["relative": "file:///tmp/a.jpg"]], format: .binary, options: 0)
            return ["Provider": "com.apple.wallpaper.choice.image", "Files": [], "Configuration": config]
        }
        let store: [String: Any] = [
            "Displays": ["37D8832A": [
                "Type": "individual",
                "Desktop": ["Content": ["Choices": [try choice(desktopAssetID)]]],
                "Idle": ["Content": ["Choices": [try choice(idleAssetID)]]],
            ]],
            "SystemDefault": ["Type": "individual", "Content": ["Choices": [try choice(nil)]]],
        ]
        return try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
    }

    let lumen = AerialManifestEditor.lumenAssetID

    @Test func imageWallpaperIsNotLumen() throws {
        let data = try storeData(desktopAssetID: nil, idleAssetID: "737E9E24-49BE-4104-9B72-F352DE1AD2BF")
        #expect(!WallpaperSelection.references(assetID: lumen, inStore: data))
    }

    @Test func lumenOnDesktopIsDetected() throws {
        let data = try storeData(desktopAssetID: lumen, idleAssetID: nil)
        #expect(WallpaperSelection.references(assetID: lumen, inStore: data))
    }

    @Test func lumenAsScreenSaverIsDetected() throws {
        let data = try storeData(desktopAssetID: nil, idleAssetID: lumen)
        #expect(WallpaperSelection.references(assetID: lumen, inStore: data))
    }

    @Test func unreadableStoreIsNotLumen() {
        #expect(!WallpaperSelection.references(assetID: lumen, inStore: Data("garbage".utf8)))
    }
}
