import Foundation

/// Keeps the lock screen showing the desktop video, through the "Lumen" aerial slot.
///
/// Energy rules: the slot is only touched when its video really changes, rapid changes
/// (playlist advances, clicks) are coalesced, `WallpaperAgent` is restarted only after an
/// actual change, and HEVC conversions never run on battery (a running one is cancelled).
@MainActor
public final class LockScreenController {
    public typealias Converter = @MainActor (_ source: URL, _ destination: URL) async throws -> Void

    /// Short French messages for the user.
    public var onNotice: ((String) -> Void)?

    private let editor: AerialManifestEditor
    private let cache: LockScreenCache
    private let importer: VideoImporter
    private let convert: Converter
    private let restartAgent: @MainActor () -> Void
    private let slotUpdateDelay: Duration

    private var isEnabled = false
    private var isOnBattery = false
    private var isScreenLocked = false
    private var wanted: Video?
    private var pendingRefresh: Task<Void, Never>?
    private var conversion: Task<Void, Never>?
    private var agentRestartPending = false

    public init(
        editor: AerialManifestEditor, cache: LockScreenCache, importer: VideoImporter,
        convert: @escaping Converter = { try await HEVCConverter.convert($0, to: $1) },
        restartAgent: @escaping @MainActor () -> Void,
        slotUpdateDelay: Duration = .seconds(30)
    ) {
        self.editor = editor
        self.cache = cache
        self.importer = importer
        self.convert = convert
        self.restartAgent = restartAgent
        self.slotUpdateDelay = slotUpdateDelay
    }

    /// Enabling applies the current video right away; disabling removes Lumen's entry.
    public func setEnabled(_ enabled: Bool, current: Video?) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        wanted = current
        pendingRefresh?.cancel()
        if enabled {
            refresh()
        } else {
            conversion?.cancel()
            disable()
        }
    }

    /// Follows the desktop after `slotUpdateDelay`, so only the last of several quick changes counts.
    public func desktopVideoDidChange(_ video: Video?) {
        wanted = video
        guard isEnabled else { return }
        pendingRefresh?.cancel()
        let delay = slotUpdateDelay
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    public func conditionsDidChange(_ conditions: PlaybackConditions) {
        let wasOnBattery = isOnBattery
        let wasLocked = isScreenLocked
        isOnBattery = conditions.isOnBattery
        isScreenLocked = conditions.isScreenLocked
        if isOnBattery && !wasOnBattery {
            conversion?.cancel()
        }
        if wasOnBattery && !isOnBattery {
            refresh()
        }
        if wasLocked && !isScreenLocked && agentRestartPending {
            agentRestartPending = false
            restartAgent()
        }
    }

    public func videoWasDeleted(_ video: Video) {
        try? cache.removeCache(for: video)
    }

    // MARK: - Private

    private func refresh() {
        guard isEnabled, let video = wanted else { return }
        let original = importer.fileURL(for: video)
        if let source = cache.readySource(for: video, originalURL: original) {
            apply(source: source, preview: importer.thumbnailURL(for: video.id))
        } else if !isOnBattery, conversion == nil {
            startConversion(of: video, from: original)
        }
    }

    private func startConversion(of video: Video, from original: URL) {
        let destination = cache.cachedURL(for: video)
        conversion = Task { [weak self, convert] in
            var failed = false
            do {
                try await convert(original, destination)
            } catch {
                failed = !Task.isCancelled && !(error is CancellationError)
            }
            guard let self else { return }
            self.conversion = nil
            if failed {
                self.onNotice?("La vidéo n'a pas pu être préparée pour l'écran de verrouillage.")
            } else if !Task.isCancelled {
                self.refresh()
            }
        }
    }

    private func apply(source: URL, preview: URL) {
        do {
            var changed = false
            if try !editor.isInstalled() {
                try editor.install(previewImageURL: preview)
                changed = true
                onNotice?("Choisis « Lumen » une fois dans Réglages Système › Fond d'écran pour l'écran de verrouillage.")
            }
            if try editor.placeInSlot(source) {
                changed = true
            }
            guard changed else { return }
            if isScreenLocked {
                agentRestartPending = true
            } else {
                restartAgent()
            }
        } catch {
            onNotice?("Impossible de mettre à jour l'écran de verrouillage : \(error.localizedDescription)")
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
}
