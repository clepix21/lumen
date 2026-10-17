import AppKit

/// One wallpaper window per connected screen, kept in sync when screens are plugged in,
/// unplugged or change resolution.
@MainActor
final class WallpaperScreens {
    /// Called after screens changed, with the windows that appeared and disappeared.
    var onChange: ((_ added: [WallpaperWindow], _ removed: [WallpaperWindow]) -> Void)?
    private(set) var windows: [WallpaperWindow] = []
    private var isShown = false
    private var observer: NSObjectProtocol?

    init() {
        windows = NSScreen.screens.map(WallpaperWindow.init(screen:))
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncWithScreens() }
        }
    }

    func show() {
        isShown = true
        for window in windows {
            window.orderFront(nil)
        }
    }

    func hide() {
        isShown = false
        for window in windows {
            window.orderOut(nil)
        }
    }

    private func syncWithScreens() {
        let screens = NSScreen.screens
        let connected = Set(screens.map(\.displayID))
        let removed = windows.filter { !connected.contains($0.displayID) }
        windows.removeAll { !connected.contains($0.displayID) }
        for window in removed {
            window.orderOut(nil)
        }

        var added: [WallpaperWindow] = []
        for screen in screens {
            if let window = windows.first(where: { $0.displayID == screen.displayID }) {
                window.fit(to: screen)
            } else {
                let window = WallpaperWindow(screen: screen)
                windows.append(window)
                added.append(window)
                if isShown {
                    window.orderFront(nil)
                }
            }
        }
        if !added.isEmpty || !removed.isEmpty {
            onChange?(added, removed)
        }
    }
}
