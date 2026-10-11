import Carbon
import AssistantCore

@MainActor
final class GlobalShortcuts {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onAction: ((AssistantAction) -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let owner = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.onAction?(id.id == 1 ? .writeEnglish : .understandEnglish) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(write: Shortcut, understand: Shortcut) throws {
        guard write.keyCode != understand.keyCode || write.modifiers != understand.modifiers else {
            throw AssistantFailure.shortcutConflict
        }
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        for (index, shortcut) in [write, understand].enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x454E4743, id: UInt32(index + 1))
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                references.forEach { UnregisterEventHotKey($0) }; references.removeAll()
                throw AssistantFailure.shortcutConflict
            }
            references.append(reference)
        }
    }
    deinit {
        references.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
