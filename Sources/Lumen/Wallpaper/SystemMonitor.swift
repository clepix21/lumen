import AppKit
import IOKit.ps
import LumenCore

/// Tracks the system state that decides whether the wallpaper should play.
/// Driven entirely by notifications: no polling.
@MainActor
final class SystemMonitor {
    var onChange: ((PlaybackConditions) -> Void)?
    private(set) var conditions = PlaybackConditions()

    private let window: NSWindow
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    init(window: NSWindow) {
        self.window = window
        conditions.isOccluded = !window.occlusionState.contains(.visible)
        conditions.isOnBattery = Self.isOnBattery()

        observe(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification, object: window) { monitor in
            monitor.conditions.isOccluded = !monitor.window.occlusionState.contains(.visible)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.conditions.isScreenAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.conditions.isScreenAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.conditions.isSessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.conditions.isSessionActive = true }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.conditions.isScreenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.conditions.isScreenLocked = false }

        startPowerNotifications()
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
