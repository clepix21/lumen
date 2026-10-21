import AppKit

/// One wallpaper window per connected screen, kept in sync when screens are plugged in,
/// unplugged or change resolution. The main screen (with the menu bar) comes first.
/// Which windows are visible is decided by `AppModel`.
@MainActor
final class WallpaperScreens {
    /// Called after screens changed, with the windows that appeared and disappeared.
    var onChange: ((_ added: [WallpaperWindow], _ removed: [WallpaperWindow]) -> Void)?
    private(set) var windows: [WallpaperWindow] = []
    private var observer: NSObjectProtocol?

    init() {
        windows = NSScreen.screens.map(WallpaperWindow.init(screen:))
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncWithScreens() }
        }
    }

    private func syncWithScreens() {
        let screens = NSScreen.screens
        let connected = Set(screens.map(\.displayID))
        let removed = windows.filter { !connected.contains($0.displayID) }
        for window in removed {
            window.orderOut(nil)
        }

        var added: [WallpaperWindow] = []
        var ordered: [WallpaperWindow] = []
        for screen in screens {
            if let window = windows.first(where: { $0.displayID == screen.displayID }) {
                window.fit(to: screen)
                ordered.append(window)
            } else {
                let window = WallpaperWindow(screen: screen)
                ordered.append(window)
                added.append(window)
            }
        }
        // Keep the menu bar screen first, as NSScreen.screens does.
        windows = ordered
        if !added.isEmpty || !removed.isEmpty {
            onChange?(added, removed)
        }
    }
}
