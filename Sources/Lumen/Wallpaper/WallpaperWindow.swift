import AppKit

/// Borderless window sitting at the desktop level (below the desktop icons) on every Space,
/// covering one screen.
@MainActor
final class WallpaperWindow: NSWindow {
    let playerView = NSView()
    /// The display this window covers; stays stable while the screen is connected.
    let displayID: CGDirectDisplayID
    /// Identifies the screen across launches (used to remember its own wallpaper).
    let screenKey: String
    /// The screen's name, e.g. "Écran intégré" or "DELL U2723QE".
    let screenName: String

    init(screen: NSScreen) {
        displayID = screen.displayID
        screenKey = screen.persistentKey
        screenName = screen.localizedName
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

    /// The display's UUID, which survives reboots and reconnections (unlike `displayID`).
    var persistentKey: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return String(displayID)
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
