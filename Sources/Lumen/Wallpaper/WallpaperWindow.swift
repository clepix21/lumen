import AppKit

/// Borderless window sitting at the desktop level (below the desktop icons) on every Space.
@MainActor
final class WallpaperWindow: NSWindow {
    let playerView = NSView()
    private var screenObserver: NSObjectProtocol?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false

        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor
        contentView = playerView
        setFrame(screen.frame, display: false)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fitToMainScreen()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The screen holding the menu bar (`NSScreen.main` would follow keyboard focus instead).
    func fitToMainScreen() {
        guard let screen = NSScreen.screens.first else { return }
        setFrame(screen.frame, display: true)
    }
}
