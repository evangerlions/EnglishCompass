import AppKit
import XCTest
@testable import EnglishCompass

final class NativeTextEditorTests: XCTestCase {
    @MainActor func testChatReturnSubmitsButShiftReturnInsertsNewline() throws {
        let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        let window = editorWindow(editor)
        defer { window.close() }
        var sends = 0
        editor.onSubmit = { sends += 1 }
        editor.string = "Question"
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        for key: UInt16 in [36, 76] {
            editor.keyDown(with: try returnEvent(keyCode: key))
        }
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(editor.string, "Question")
        editor.keyDown(with: try returnEvent(modifiers: .shift))
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(editor.string, "Question\n")
    }

    @MainActor func testNormalEditorReturnStillInsertsNewline() throws {
        let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        let window = editorWindow(editor)
        defer { window.close() }
        editor.keyDown(with: try returnEvent())
        XCTAssertEqual(editor.string, "\n")
    }

    @MainActor func testCompositionReturnDoesNotSend() throws {
        let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        var sends = 0
        editor.onSubmit = { sends += 1 }
        editor.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        editor.keyDown(with: try returnEvent())
        XCTAssertEqual(sends, 0)
    }

    private func returnEvent(keyCode: UInt16 = 36, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                                      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode))
    }

    @MainActor private func editorWindow(_ editor: NSTextView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeFirstResponder(editor)
        return window
    }

    @MainActor func testPlaceholderAndTypedTextShareFirstGlyphBaseline() throws {
        for size: CGFloat in [13, 15] {
            for width: CGFloat in [220, 480] {
                let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
                editor.font = .systemFont(ofSize: size)
                editor.textContainerInset = NSSize(width: 12, height: 10)
                editor.textContainer?.lineFragmentPadding = 0
                editor.placeholder = "Paste or type your text..."
                let placeholderOrigin = editor.placeholderFirstGlyphOrigin
                XCTAssertEqual(editor.string, "")
                editor.string = editor.placeholder
                let layout = try XCTUnwrap(editor.layoutManager)
                let container = try XCTUnwrap(editor.textContainer)
                layout.ensureLayout(for: container)
                let line = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                let glyph = layout.location(forGlyphAt: 0)
                XCTAssertEqual(placeholderOrigin.x, editor.textContainerOrigin.x + line.minX + glyph.x, accuracy: 0.01)
                XCTAssertEqual(placeholderOrigin.y, editor.textContainerOrigin.y + line.minY + glyph.y, accuracy: 0.01)
            }
        }
    }
    @MainActor func testPlaceholderNeverBecomesInputAndDrawingDoesNotMoveSelection() {
        let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
        editor.placeholder = "Visual hint only."
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        _ = editor.placeholderFirstGlyphOrigin
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
        editor.string = "Actual input"
        editor.placeholder = "Another hint"
        XCTAssertEqual(editor.string, "Actual input")
    }
}
