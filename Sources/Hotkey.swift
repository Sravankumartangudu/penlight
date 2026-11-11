// Hotkey.swift — ⌃⌥Space opens Penlight for the box you're typing in, button or not.

import Carbon.HIToolbox

final class Hotkey {
    static let shared = Hotkey()
    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    static let label = "⌃⌥Space"

    func set(_ on: Bool) { on ? register() : unregister() }

    private func register() {
        guard ref == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { Hotkey.shared.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x504E4C54), id: 1)   // "PNLT"
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { log.error("hotkey taken (\(status, privacy: .public))"); ref = nil }
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
