import AppKit
import LumenCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel?
    private var wallpaperWindow: WallpaperWindow?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let paths = LumenPaths.standard()
        let isFirstLaunch = !FileManager.default.fileExists(atPath: paths.libraryFile.path)
        let window = WallpaperWindow(screen: screen)
        let model = AppModel(paths: paths, window: window)
        model.onSettingsChange = { [weak model] old, new in
            guard new.launchAtLogin != old.launchAtLogin else { return }
            Self.applyLoginItem(new.launchAtLogin, model: model)
        }
        wallpaperWindow = window
        self.model = model

        setUpStatusItem(model: model)

        if isFirstLaunch {
            Self.applyLoginItem(model.library.settings.launchAtLogin, model: model)
        }
        if model.library.videos.isEmpty {
            showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu bar

    private func setUpStatusItem(model: AppModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Lumen")
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model) { [weak self] in
            self?.popover.performClose(nil)
            self?.showMainWindow()
        })
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Main window

    /// Shows the main window; the Dock icon appears while it is open.
    func showMainWindow() {
        guard let model else { return }
        NSApp.setActivationPolicy(.regular)
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Lumen"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: MainWindowView(model: model))
            window.delegate = self
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Login item

    private static func applyLoginItem(_ enabled: Bool, model: AppModel?) {
        do {
            try LoginItem.set(enabled: enabled)
        } catch {
            model?.lastError = "Impossible de modifier le lancement au démarrage : \(error.localizedDescription)"
        }
    }
}
