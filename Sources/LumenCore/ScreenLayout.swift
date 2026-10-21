import Foundation

/// Screens that show the same thing; they share one player, so one decoder.
public struct ScreenGroup: Equatable, Sendable {
    public let selection: Selection
    public let screenIDs: [String]

    public init(selection: Selection, screenIDs: [String]) {
        self.selection = selection
        self.screenIDs = screenIDs
    }
}

/// What each screen shows. The main screen always shows the library's selection; with
/// `sameOnAllScreens` off, other screens may have their own (`overrides`, keyed by screen ID).
public struct ScreenLayout: Codable, Equatable, Sendable {
    public var sameOnAllScreens = true
    public var overrides: [String: Selection] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sameOnAllScreens = try container.decodeIfPresent(Bool.self, forKey: .sameOnAllScreens) ?? true
        overrides = try container.decodeIfPresent([String: Selection].self, forKey: .overrides) ?? [:]
    }

    /// Groups `screens` (main screen first) by what they show, keeping their order.
    public func groups(screens: [String], mainSelection: Selection) -> [ScreenGroup] {
        var groups: [ScreenGroup] = []
        for (index, screen) in screens.enumerated() {
            let selection = sameOnAllScreens || index == 0 ? mainSelection : (overrides[screen] ?? mainSelection)
            if let existing = groups.firstIndex(where: { $0.selection == selection }) {
                groups[existing] = ScreenGroup(selection: selection, screenIDs: groups[existing].screenIDs + [screen])
            } else {
                groups.append(ScreenGroup(selection: selection, screenIDs: [screen]))
            }
        }
        return groups
    }

    /// Drops overrides that point at a deleted video or playlist.
    mutating func forget(videoID: UUID? = nil, playlistID: UUID? = nil) {
        overrides = overrides.filter { _, selection in
            switch selection {
            case .video(let id): return id != videoID
            case .playlist(let id): return id != playlistID
            case .none: return true
            }
        }
    }
}
