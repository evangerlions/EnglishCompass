import AppKit
import ApplicationServices
import AssistantCore

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

    func capture(_ action: AssistantAction) throws -> CapturedTarget {
        guard trusted else { throw AssistantFailure.permission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw AssistantFailure.noText }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = attribute(application, kAXFocusedUIElementAttribute) else { throw AssistantFailure.noText }
        let element = focused as! AXUIElement
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        guard !subrole.contains("Secure"), !role.contains("Secure") else { throw AssistantFailure.secureField }
        let selected = attribute(element, kAXSelectedTextAttribute) as? String ?? ""
        let editable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
        let value = editable ? attribute(element, kAXValueAttribute) as? String : nil
        let selection = selectedRange(element)
        let snapshot: DraftSnapshot
        let writebackEligible: Bool
        if !selected.isEmpty {
            if let value, let selection, let draft = try? DraftSnapshot(fullText: value, range: selection), draft.input == selected {
                snapshot = draft
                writebackEligible = true
            } else {
                // Read-only selections can be translated, never written back.
                snapshot = try DraftSnapshot(fullText: selected, range: NSRange(location: 0, length: (selected as NSString).length))
                writebackEligible = false
            }
        } else {
            guard action == .writeEnglish else { throw AssistantFailure.selectText }
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  isSettable(element, kAXValueAttribute) else { throw AssistantFailure.noText }
            snapshot = try DraftSnapshot(fullText: value, range: NSRange(location: 0, length: (value as NSString).length))
            writebackEligible = true
        }
        let window = attribute(application, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        return CapturedTarget(app: app, window: window, element: element, snapshot: snapshot, anchor: bounds(element), writebackEligible: writebackEligible)
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
