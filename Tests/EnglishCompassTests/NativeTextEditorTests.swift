import AppKit
import XCTest
@testable import EnglishCompass

final class NativeTextEditorTests: XCTestCase {
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
