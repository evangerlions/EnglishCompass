import AppKit
import ApplicationServices
import AssistantCore
import Carbon.HIToolbox

struct CapturedTarget {
    let app: NSRunningApplication
    let window: AXUIElement?
    let element: AXUIElement
    let snapshot: DraftSnapshot
    let anchor: CGRect?
    let writebackEligible: Bool
}

@MainActor
final class AccessibilityBridge {
    var trusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func capture(_ action: AssistantAction) async throws -> CapturedTarget {
        guard trusted else { throw AssistantFailure.permission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw AssistantFailure.noText }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let focusedElement: AXUIElement
        if let focused = attribute(application, kAXFocusedUIElementAttribute) {
            focusedElement = focused as! AXUIElement
        } else {
            focusedElement = application
        }
        let role = attribute(focusedElement, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(focusedElement, kAXSubroleAttribute) as? String ?? ""
        guard !subrole.contains("Secure"), !role.contains("Secure") else { throw AssistantFailure.secureField }

        // First inspect the element under the pointer. Browser selections often do
        // not become the focused AX element, while the mouse remains at the end of
        // the selected range after mouse-up.
        var selection: (text: String, source: AXUIElement)?
        if let location = CGEvent(source: nil)?.location,
           let hit = element(at: location) {
            selection = selectedTextInHierarchy(startingAt: hit)
        }
        // Native editors normally expose selection from their focused element.
        if selection == nil {
            selection = selectedTextInHierarchy(startingAt: focusedElement)
        }

        let selected = selection?.text ?? ""
        let selectionSource = selection?.source ?? focusedElement
        let element = focusedElement
        let editable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
        let value = editable ? attribute(element, kAXValueAttribute) as? String : nil
        let snapshot: DraftSnapshot
        let writebackEligible: Bool
        if !selected.isEmpty {
            // Prefer the source element that actually yielded the selection.
            let sourceValue = editable ? (value ?? attribute(selectionSource, kAXValueAttribute) as? String) : nil
            if let sourceValue, sourceValue == selected,
               let range = selectedRange(selectionSource),
               let draft = try? DraftSnapshot(fullText: sourceValue, range: range), draft.input == selected {
                snapshot = draft
                writebackEligible = true
            } else if let sourceValue, !sourceValue.isEmpty {
                snapshot = try DraftSnapshot(fullText: sourceValue, range: NSRange(location: 0, length: (sourceValue as NSString).length))
                writebackEligible = true
            } else {
                // Read-only selections (web pages, labels) — translate only.
                snapshot = try DraftSnapshot(fullText: selected, range: NSRange(location: 0, length: (selected as NSString).length))
                writebackEligible = false
            }
        } else {
            // 3. AX could not read the selection. Fall back to simulating Cmd+C
            //    (the approach used by dictionary/lookup apps). The result is
            //    read-only; writeback stays on the AX path.
            guard action == .writeEnglish || action == .understandEnglish else { throw AssistantFailure.selectText }
            if let copied = await copySelectedText(from: app) {
                snapshot = try DraftSnapshot(fullText: copied, range: NSRange(location: 0, length: (copied as NSString).length))
                writebackEligible = false
            } else {
                throw AssistantFailure.noText
            }
        }
        let window = attribute(application, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        return CapturedTarget(app: app, window: window, element: element, snapshot: snapshot, anchor: bounds(element), writebackEligible: writebackEligible)
    }

    /// Simulate Cmd+C in the captured source application and read the new
    /// pasteboard value. Restore the user's prior clipboard only if nobody else
    /// has changed it in the meantime.
    private func copySelectedText(from app: NSRunningApplication) async -> String? {
        guard !app.isTerminated else { return nil }
        let pasteboard = NSPasteboard.general
        let oldItems = pasteboard.pasteboardItems
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount

        // Target the original application explicitly. A global hotkey handler may
        // otherwise make this accessory app frontmost before the event is handled.
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.postToPid(app.processIdentifier)
        keyUp?.postToPid(app.processIdentifier)

        // Clipboard providers are asynchronous. Poll briefly instead of assuming
        // one fixed delay works for every application.
        var copied: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != clearedChangeCount {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        let copyChangeCount = pasteboard.changeCount

        let items = oldItems
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard pasteboard.changeCount == copyChangeCount else { return }
            pasteboard.clearContents()
            items?.forEach { item in
                item.types.forEach { type in
                    if let data = item.data(forType: type) {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
        guard let text = copied, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    func replace(_ text: String, in target: CapturedTarget) throws {
        guard target.writebackEligible else { throw AssistantFailure.unsupportedWriteback }
        guard trusted, !target.app.isTerminated else { throw AssistantFailure.changedTarget }
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard currentPID == target.app.processIdentifier || currentPID == ProcessInfo.processInfo.processIdentifier else {
            throw AssistantFailure.changedTarget
        }
        let application = AXUIElementCreateApplication(target.app.processIdentifier)
        guard let focused = attribute(application, kAXFocusedUIElementAttribute), CFEqual(focused, target.element) else {
            throw AssistantFailure.changedTarget
        }
        if let originalWindow = target.window {
            guard let currentWindow = attribute(application, kAXFocusedWindowAttribute), CFEqual(originalWindow, currentWindow) else {
                throw AssistantFailure.changedTarget
            }
        }
        guard let current = attribute(target.element, kAXValueAttribute) as? String else {
            throw AssistantFailure.unsupportedWriteback
        }
        let replacement = try target.snapshot.replacing(with: text, current: current)
        guard isSettable(target.element, kAXValueAttribute) else { throw AssistantFailure.unsupportedWriteback }
        // AX writes only: never paste, synthesize keystrokes, or send Enter.
        let error = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, replacement as CFString)
        guard error == .success else { throw AssistantFailure.unsupportedWriteback }
        target.app.activate(options: [])
        _ = AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var range = CFRange(location: target.snapshot.range.location + (text as NSString).length, length: 0)
        if let value = AXValueCreate(.cfRange, &range) {
            _ = AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }

    func canWrite(_ target: CapturedTarget) -> Bool {
        guard let value = attribute(target.element, kAXValueAttribute) as? String else { return false }
        return target.writebackEligible && value.utf16.elementsEqual(target.snapshot.fullText.utf16) && isSettable(target.element, kAXValueAttribute)
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        return hit
    }

    private func selectedTextInHierarchy(startingAt start: AXUIElement) -> (text: String, source: AXUIElement)? {
        var current = start
        // Web accessibility trees can be considerably deeper than native editor
        // trees; stop at the application boundary rather than an arbitrary 6 hops.
        for _ in 0..<24 {
            let role = attribute(current, kAXRoleAttribute) as? String ?? ""
            let subrole = attribute(current, kAXSubroleAttribute) as? String ?? ""
            if subrole.contains("Secure") || role.contains("Secure") { return nil }
            if let text = attribute(current, kAXSelectedTextAttribute) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (text, current)
            }
            guard role != kAXApplicationRole,
                  let rawParent = attribute(current, kAXParentAttribute) else { break }
            current = rawParent as! AXUIElement
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private func bounds(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
