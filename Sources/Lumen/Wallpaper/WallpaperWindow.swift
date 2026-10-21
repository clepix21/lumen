import AppKit

/// Borderless window sitting at the desktop level (below the desktop icons) on every Space,
/// covering one screen.
@MainActor
final class WallpaperWindow: NSWindow {
    let playerView = NSView()
    /// The display this window covers; stays stable while the screen is connected.
    let displayID: CGDirectDisplayID

    init(screen: NSScreen) {
        displayID = screen.displayID
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
