import AppKit
import Carbon
import Combine

/// Carbon's registered hot-key API receives only the configured shortcut. It
/// does not install a global keyboard monitor or require Accessibility access.
@MainActor
final class ShortcutController: ObservableObject {
    @Published private(set) var error: String?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func configure(enabled: Bool, choice: IslandShortcut) {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        error = nil
        guard enabled else { return }
        let key: UInt32
        let modifiers: UInt32
        switch choice {
        case .ctrlOptionSpace: key = UInt32(kVK_Space); modifiers = UInt32(controlKey | optionKey)
        case .cmdShiftSpace: key = UInt32(kVK_Space); modifiers = UInt32(cmdKey | shiftKey)
        case .ctrlOptionN: key = UInt32(kVK_ANSI_N); modifiers = UInt32(controlKey | optionKey)
        }
        let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4E49534C, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { error = String(localized: "The island shortcut is already in use or unavailable. Choose another shortcut in Settings.") }
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
