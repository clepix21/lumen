import AppKit
import IOKit.ps
import LumenCore

/// Tracks the system state that decides whether the wallpaper should play.
/// Driven entirely by notifications: no polling.
@MainActor
final class SystemMonitor {
    var onChange: ((PlaybackConditions) -> Void)?
    private(set) var conditions = PlaybackConditions()

    private var windows: [NSWindow] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    /// `windows` are the wallpaper windows; the desktop counts as hidden only when all are covered.
    init(windows: [NSWindow]) {
        conditions.isOnBattery = Self.isOnBattery()

        // Occlusion is checked for whichever window changed, against the current list.
        observe(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification) { monitor in
            monitor.updateOcclusion()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.conditions.isScreenAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.conditions.isScreenAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.conditions.isSessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.conditions.isSessionActive = true }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.conditions.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.conditions.isScreenLocked = false }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.conditions.isScreenSaverRunning = true }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.conditions.isScreenSaverRunning = false }

        startPowerNotifications()
        setWindows(windows)
    }

    /// Replaces the watched wallpaper windows (screens plugged in or out).
    func setWindows(_ windows: [NSWindow]) {
        self.windows = windows
        updateOcclusion()
        onChange?(conditions)
    }

    private func updateOcclusion() {
        conditions.isOccluded = !windows.isEmpty && windows.allSatisfy { !$0.occlusionState.contains(.visible) }
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
        update: @escaping @MainActor (SystemMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
                self.onChange?(self.conditions)
            }
        }
        observers.append((center, token))
    }

    private func startPowerNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // The source is scheduled on the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated {
                let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
                let onBattery = SystemMonitor.isOnBattery()
                guard onBattery != monitor.conditions.isOnBattery else { return }
                monitor.conditions.isOnBattery = onBattery
                monitor.onChange?(monitor.conditions)
            }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    nonisolated static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    func stop() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil
    }
}
