import AppKit
import LumenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var demoWindow: WallpaperWindow?
    private var demoPlayer: WallpaperPlayer?
    private var demoMonitor: SystemMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Lumen")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        if let path = ProcessInfo.processInfo.environment["LUMEN_DEMO_VIDEO"], let screen = NSScreen.main {
            startDemo(url: URL(fileURLWithPath: path), screen: screen)
        }
    }

    private func startDemo(url: URL, screen: NSScreen) {
        let window = WallpaperWindow(screen: screen)
        window.orderFront(nil)
        let player = WallpaperPlayer(hostView: window.playerView)
        player.setMuted(true)
        player.load(url: url, loop: true)
        let monitor = SystemMonitor(window: window)
        let apply: (PlaybackConditions) -> Void = { conditions in
            let play = PlaybackPolicy.shouldPlay(conditions, settings: Settings())
            NSLog("Lumen demo: %@ -> %@", String(describing: conditions), play ? "play" : "pause")
            player.setPlaying(play)
        }
        monitor.onChange = apply
        apply(monitor.conditions)
        demoWindow = window
        demoPlayer = player
        demoMonitor = monitor
    }
}
