import AppKit
import XCTest
@testable import EnglishCompass

private final class PasteProbe: NSTextView {
    var pasted = false
    override func paste(_ sender: Any?) { pasted = true }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
}

@MainActor private final class CloseProbe: NSObject, NSWindowDelegate {
    var closeRequests = 0
    var allowsClose = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequests += 1
        return allowsClose
    }
}

final class ApplicationMenusTests: XCTestCase {
    @MainActor func testCloseWindowShortcutUsesTheFocusedWindow() throws {
        let menu = ApplicationMenus.make()
        let close = try XCTUnwrap(menu.item(withTitle: "File")?.submenu?.item(withTitle: "Close Window"))
        let shared = ApplicationMenus.closeWindowItem()
        for item in [close, shared] {
            XCTAssertEqual(item.keyEquivalent, "w")
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
            XCTAssertEqual(item.action, #selector(NSWindow.performClose(_:)))
            XCTAssertNil(item.target)
        }
    }

    @MainActor func testCloseWindowActionRespectsExistingWindowDelegate() throws {
        let item = ApplicationMenus.closeWindowItem()
        let action = try XCTUnwrap(item.action)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let delegate = CloseProbe()
        window.delegate = delegate
        defer { window.delegate = nil; window.close() }
        window.orderFront(nil)

        window.perform(action, with: item)
        XCTAssertEqual(delegate.closeRequests, 1)
        XCTAssertTrue(window.isVisible, "The assistant delegate can handle closing without destroying its reusable window")

        delegate.allowsClose = true
        window.perform(action, with: item)
        XCTAssertEqual(delegate.closeRequests, 2)
        XCTAssertFalse(window.isVisible, "Ordinary windows such as Settings close when their delegate allows it")
    }

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
