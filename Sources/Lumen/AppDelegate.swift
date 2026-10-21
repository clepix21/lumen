import AppKit
import Combine
import LumenCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var model: AppModel?
    private var wallpaperScreens: WallpaperScreens?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var lockScreenController: LockScreenController?
    private var messageSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let paths = LumenPaths.standard()
        let isFirstLaunch = !FileManager.default.fileExists(atPath: paths.libraryFile.path)
        let screens = WallpaperScreens()
        let model = AppModel(paths: paths, screens: screens)
        let lockScreen = Self.makeLockScreenController(paths: paths, model: model)
        model.onSettingsChange = { [weak model] old, new in
            if new.launchAtLogin != old.launchAtLogin {
                Self.applyLoginItem(new.launchAtLogin, model: model)
            }
            if new.lockScreenEnabled != old.lockScreenEnabled {
                lockScreen?.setEnabled(new.lockScreenEnabled, current: model?.currentVideo)
            }
        }
        wallpaperScreens = screens
        self.model = model
        lockScreenController = lockScreen

        setUpStatusItem(model: model)
        // Messages are shown by the main window; open it if one arrives while it is closed.
        messageSubscription = model.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard message != nil, self?.mainWindow?.isVisible != true else { return }
                self?.showMainWindow()
            }

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
        item.button?.image = NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Lumen")
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let model else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Built on demand and released on close, so it does not refresh while hidden.
            popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model) { [weak self] in
                self?.popover.performClose(nil)
                self?.showMainWindow()
            })
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
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
            window.delegate = self
            window.center()
            mainWindow = window
        }
        // The content is released on close; rebuild it when the window comes back.
        if !(mainWindow?.contentView is FileDropHostingView<MainWindowView>) {
            mainWindow?.contentView = makeMainContent(model: model)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeMainContent(model: AppModel) -> NSView {
        let content = FileDropHostingView(rootView: MainWindowView(model: model))
        content.onDropFiles = { [weak model] urls in
            Task { await model?.importVideos(urls) }
        }
        content.onTargetedChange = { [weak model] targeted in model?.isDropTargeted = targeted }
        return content
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
        // Release the SwiftUI content so it stops refreshing while the window is closed.
        window.contentView = nil
    }

    // MARK: - Lock screen

    /// Lock screen video needs macOS 26 or later; returns nil before that.
    private static func makeLockScreenController(paths: LumenPaths, model: AppModel) -> LockScreenController? {
        guard #available(macOS 26, *) else { return nil }
        let controller = LockScreenController(
            editor: .standard(), cache: LockScreenCache(paths: paths), importer: model.importer,
            restartAgent: restartWallpaperAgent
        )
        controller.onNotice = { [weak model] message in model?.lastError = message }
        model.onCurrentVideoChange = { [weak controller] video in controller?.desktopVideoDidChange(video) }
        model.onConditionsChange = { [weak controller] conditions in controller?.conditionsDidChange(conditions) }
        model.onVideoDeleted = { [weak controller] video in controller?.videoWasDeleted(video) }
        controller.conditionsDidChange(model.conditions)
        controller.setEnabled(model.library.settings.lockScreenEnabled, current: model.currentVideo)
        return controller
    }

    /// `WallpaperAgent` only re-reads a swapped video after a restart; launchd relaunches it.
    private static func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in }
        try? task.run()
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
