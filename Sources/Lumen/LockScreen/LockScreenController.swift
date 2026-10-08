import AppKit
import LumenCore

/// Keeps the lock screen showing the desktop video, through the "Lumen" aerial slot.
///
/// The slot is refreshed by hard-linking the ready HEVC file (no copy), then restarting
/// `WallpaperAgent` so it re-reads the slot. Conversions run one at a time, newest request
/// first, and wait for AC power.
@MainActor
final class LockScreenController {
    /// Short French messages for the user (shown as an alert).
    var onNotice: ((String) -> Void)?

    private let editor: AerialManifestEditor
    private let cache: LockScreenCache
    private let importer: VideoImporter
    private var isEnabled = false
    private var isOnBattery = false
    private var isScreenLocked = false
    private var wanted: Video?
    private var converting: UUID?
    private var agentRestartPending = false

    init(editor: AerialManifestEditor, cache: LockScreenCache, importer: VideoImporter) {
        self.editor = editor
        self.cache = cache
        self.importer = importer
    }

    func setEnabled(_ enabled: Bool, current: Video?) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            wanted = current
            refresh()
        } else {
            wanted = nil
            disable()
        }
    }

    func desktopVideoDidChange(_ video: Video?) {
        wanted = video
        guard isEnabled else { return }
        refresh()
    }

    func conditionsDidChange(_ conditions: PlaybackConditions) {
        let wasOnBattery = isOnBattery
        let wasLocked = isScreenLocked
        isOnBattery = conditions.isOnBattery
        isScreenLocked = conditions.isScreenLocked
        if wasOnBattery && !isOnBattery {
            refresh()
        }
        if wasLocked && !isScreenLocked && agentRestartPending {
            restartAgent()
        }
    }

    func videoWasDeleted(_ video: Video) {
        try? cache.removeCache(for: video)
    }

    // MARK: - Private

    private func refresh() {
        guard isEnabled, let video = wanted else { return }
        let original = importer.fileURL(for: video)
        if let source = cache.readySource(for: video, originalURL: original) {
            install(source: source, preview: importer.thumbnailURL(for: video.id))
        } else if !isOnBattery, converting == nil {
            convert(video, from: original)
        }
    }

    private func convert(_ video: Video, from original: URL) {
        converting = video.id
        let destination = cache.cachedURL(for: video)
        Task {
            do {
                try await HEVCConverter.convert(original, to: destination)
            } catch {
                onNotice?("La vidéo n'a pas pu être préparée pour l'écran de verrouillage.")
            }
            converting = nil
            refresh()
        }
    }

    private func install(source: URL, preview: URL) {
        do {
            if try !editor.isInstalled() {
                try editor.install(previewImageURL: preview)
                onNotice?("Choisis « Lumen » une fois dans Réglages Système › Fond d'écran pour l'écran de verrouillage.")
            }
            try placeInSlot(source)
            if isScreenLocked {
                agentRestartPending = true
            } else {
                restartAgent()
            }
        } catch {
            onNotice?("Impossible de mettre à jour l'écran de verrouillage : \(error.localizedDescription)")
        }
    }

    /// Atomically replaces the slot, linking instead of copying when both files share a volume.
    private func placeInSlot(_ source: URL) throws {
        let fileManager = FileManager.default
        let slot = editor.slotURL
        let staging = slot.deletingLastPathComponent().appendingPathComponent(".lumen-staging.mov")
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.linkItem(at: source, to: staging)
        } catch {
            try fileManager.copyItem(at: source, to: staging)
        }
        if fileManager.fileExists(atPath: slot.path) {
            _ = try fileManager.replaceItemAt(slot, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: slot)
        }
    }

    private func disable() {
        do {
            let wasInstalled = try editor.isInstalled()
            try editor.uninstall()
            if wasInstalled {
                restartAgent()
                onNotice?("Choisis un autre fond d'écran dans Réglages Système › Fond d'écran.")
            }
        } catch {
            onNotice?("Impossible de retirer Lumen de l'écran de verrouillage : \(error.localizedDescription)")
        }
    }

    /// `WallpaperAgent` only re-reads a swapped video after a restart; launchd relaunches it.
    private func restartAgent() {
        agentRestartPending = false
        let caches = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.aerials"
        )
        if let items = try? FileManager.default.contentsOfDirectory(atPath: caches.path) {
            for item in items where item.hasSuffix(".bmp") {
                try? FileManager.default.removeItem(at: caches.appendingPathComponent(item))
            }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
