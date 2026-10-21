import Carbon.HIToolbox

/// System-wide shortcuts (⌃⌥⌘P, ⌃⌥⌘→, ⌃⌥⌘←, ⌃⌥⌘M) through Carbon hot keys, which need no
/// accessibility permission: macOS only tells Lumen when one of these exact keys is pressed.
@MainActor
final class GlobalShortcuts {
    enum Action: UInt32, CaseIterable {
        case togglePause = 1, next, previous, toggleMute

        var keyCode: Int {
            switch self {
            case .togglePause: kVK_ANSI_P
            case .next: kVK_RightArrow
            case .previous: kVK_LeftArrow
            case .toggleMute: kVK_ANSI_M
            }
        }
    }

    var onAction: ((Action) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4C554D4E // "LUMN"

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKeys.isEmpty else { return }
        installHandlerIfNeeded()
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            // A shortcut already taken by another app is skipped; the others still work.
            if RegisterEventHotKey(UInt32(action.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                hotKeys.append(ref)
            }
        }
    }

    private func unregister() {
        for ref in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalShortcuts.signature,
                  let action = Action(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().onAction?(action)
            }
            return noErr
        }, 1, &eventType, context, &handler)
    }
}
