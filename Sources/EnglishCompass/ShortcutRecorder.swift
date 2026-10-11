import AppKit
import SwiftUI
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let onRecord: (Shortcut) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton(label: label, onRecord: onRecord) }
    func updateNSView(_ view: RecorderButton, context: Context) { if !view.recording { view.title = label } }
}

final class RecorderButton: NSButton {
    var recording = false
    let onRecord: (Shortcut) -> Void
    init(label: String, onRecord: @escaping (Shortcut) -> Void) {
        self.onRecord = onRecord
        super.init(frame: .zero)
        title = label; bezelStyle = .rounded; target = self; action = #selector(record)
        setAccessibilityLabel("Record shortcut: \(label)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { true }
    @objc private func record() { recording = true; title = "Press shortcut (Esc cancels)"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = "Record again"; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.command) else { title = "Include Control or Command"; return }
        var mods: UInt32 = 0
        var names: [String] = []
        if flags.contains(.control) { mods |= UInt32(controlKey); names.append("Control") }
        if flags.contains(.option) { mods |= UInt32(optionKey); names.append("Option") }
        if flags.contains(.command) { mods |= UInt32(cmdKey); names.append("Command") }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); names.append("Shift") }
        guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return }
        names.append(key.uppercased())
        recording = false
        onRecord(Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods, label: names.joined(separator: " + ")))
    }
}
