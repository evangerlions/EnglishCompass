import AppKit
import XCTest
@testable import EnglishCompass

private final class PasteProbe: NSTextView {
    var pasted = false
    override func paste(_ sender: Any?) { pasted = true }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
}

final class ApplicationMenusTests: XCTestCase {
    @MainActor func testPasteActionIsImplementedByNativeEditorWithoutReadingClipboard() throws {
        let menu = ApplicationMenus.make()
        let editor = PasteProbe(frame: .zero)
        // The runner has no app event loop; live UI verifies keyboard dispatch.
        let paste = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu?.item(withTitle: "Paste"))
        let action = try XCTUnwrap(paste.action)
        XCTAssertTrue(editor.responds(to: action))
        editor.perform(action, with: paste)
        XCTAssertTrue(editor.pasted)
    }
    @MainActor func testStandardEditingShortcutsUseTheFocusedResponder() throws {
        let menu = ApplicationMenus.make()
        let edit = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu)
        for (title, key, selector) in [
            ("Cut", "x", "cut:"), ("Copy", "c", "copy:"),
            ("Paste", "v", "paste:"), ("Select All", "a", "selectAll:"),
            ("Undo", "z", "undo:")
        ] {
            let item = try XCTUnwrap(edit.item(withTitle: title))
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
            XCTAssertEqual(item.action, Selector(selector))
            XCTAssertNil(item.target)
        }
        let redo = try XCTUnwrap(edit.item(withTitle: "Redo"))
        XCTAssertEqual(redo.action, Selector(("redo:")))
        XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])
    }
}
