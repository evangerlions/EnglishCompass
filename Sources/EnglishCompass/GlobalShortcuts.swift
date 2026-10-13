import Carbon
import AssistantCore

@MainActor
final class GlobalShortcuts {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onShortcut: ((ShortcutKind) -> Void)?

    /// Hot key IDs are 1-based positions in `ShortcutKind.allCases`.
    private static func kind(for id: UInt32) -> ShortcutKind? {
        let index = Int(id) - 1
        return ShortcutKind.allCases.indices.contains(index) ? ShortcutKind.allCases[index] : nil
    }

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            let value = id.id
            DispatchQueue.main.async {
                if let kind = GlobalShortcuts.kind(for: value) { owner.onShortcut?(kind) }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Registers every shortcut or none: duplicates or a system rejection throw
    /// and leave nothing registered, so the caller can restore the previous set.
    func register(_ shortcuts: [ShortcutKind: Shortcut]) throws {
        let ordered = ShortcutKind.allCases.compactMap { kind in shortcuts[kind].map { (kind, $0) } }
        for (offset, entry) in ordered.enumerated() {
            for other in ordered[(offset + 1)...] where
                other.1.keyCode == entry.1.keyCode && other.1.modifiers == entry.1.modifiers {
                throw AssistantFailure.shortcutConflict
            }
        }
        unregisterAll()
        for (kind, shortcut) in ordered {
            var reference: EventHotKeyRef?
            let index = ShortcutKind.allCases.firstIndex(of: kind)!
            let id = EventHotKeyID(signature: 0x454E4743, id: UInt32(index + 1))
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                unregisterAll()
                throw AssistantFailure.shortcutConflict
            }
            references.append(reference)
        }
    }

    private func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
    }

    deinit {
        references.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
