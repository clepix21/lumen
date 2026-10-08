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
    private var lockScreenController: LockScreenController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let paths = LumenPaths.standard()
        let isFirstLaunch = !FileManager.default.fileExists(atPath: paths.libraryFile.path)
        let window = WallpaperWindow(screen: screen)
        let model = AppModel(paths: paths, window: window)
        let lockScreen = Self.makeLockScreenController(paths: paths, model: model)
        model.onSettingsChange = { [weak model] old, new in
            if new.launchAtLogin != old.launchAtLogin {
                Self.applyLoginItem(new.launchAtLogin, model: model)
            }
            if new.lockScreenEnabled != old.lockScreenEnabled {
                lockScreen?.setEnabled(new.lockScreenEnabled, current: model?.currentVideo)
            }
        }
        wallpaperWindow = window
        self.model = model
        lockScreenController = lockScreen

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

    // MARK: - Lock screen

    /// Lock screen video needs macOS 26 or later; returns nil before that.
    private static func makeLockScreenController(paths: LumenPaths, model: AppModel) -> LockScreenController? {
        guard #available(macOS 26, *) else { return nil }
        let controller = LockScreenController(
            editor: .standard(), cache: LockScreenCache(paths: paths), importer: model.importer
        )
        controller.onNotice = { [weak model] message in model?.lastError = message }
        model.onCurrentVideoChange = { [weak controller] video in controller?.desktopVideoDidChange(video) }
        model.onConditionsChange = { [weak controller] conditions in controller?.conditionsDidChange(conditions) }
        model.onVideoDeleted = { [weak controller] video in controller?.videoWasDeleted(video) }
        controller.conditionsDidChange(model.conditions)
        controller.setEnabled(model.library.settings.lockScreenEnabled, current: model.currentVideo)
        return controller
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
