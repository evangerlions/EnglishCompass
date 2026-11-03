import AppKit
import XCTest
import AssistantCore
@testable import EnglishCompass

final class DiffDemoFormattingTests: XCTestCase {
    @MainActor func testRichTextKeepsLiteralTextAndStylesOnlyChanges() throws {
        let old = "She go home.\n**literal**"
        let new = "She goes home.\n**literal**"
        let parts = TextDiff.parts(original: old, proposed: new)
        let rich = DiffDemoFormatting.highlight(parts)
        XCTAssertEqual(rich.string, parts.map(\.text).joined())
        let removed = (rich.string as NSString).range(of: "go")
        let inserted = (rich.string as NSString).range(of: "goes")
        XCTAssertEqual(rich.attribute(.strikethroughStyle, at: removed.location, effectiveRange: nil) as? Int,
                       NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(rich.attribute(.underlineStyle, at: inserted.location, effectiveRange: nil) as? Int,
                       NSUnderlineStyle.single.rawValue)
        XCTAssertNil(rich.attribute(.strikethroughStyle, at: inserted.location, effectiveRange: nil))
        let font = try XCTUnwrap(rich.attribute(.font, at: inserted.location, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font, NSFont.systemFont(ofSize: 16), "Highlights must not make whole sentences bold")
        XCTAssertTrue(rich.string.contains("**literal**"), "Inputs are literal text, not Markdown")
    }

    @MainActor func testSplitViewsReconstructExactInputStrings() {
        let old = "  Hello!\r\n\n👩🏽‍💻\t"
        let new = "Hello, world!\n👩🏽‍💻\t\n"
        let parts = TextDiff.parts(original: old, proposed: new)
        XCTAssertEqual(Array(DiffDemoFormatting.highlight(parts, keeping: .removed).string.utf16), Array(old.utf16))
        XCTAssertEqual(Array(DiffDemoFormatting.highlight(parts, keeping: .inserted).string.utf16), Array(new.utf16))
    }

    @MainActor func testFinalTextHasNoDiffDecoration() {
        let parts = TextDiff.parts(original: "go", proposed: "goes")
        let final = DiffDemoFormatting.highlight(parts, keeping: .inserted, marksChanges: false)
        XCTAssertEqual(final.string, "goes")
        XCTAssertNil(final.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(final.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(final.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    @MainActor func testWhitespaceMarkersAreDisplayOnly() {
        let text = "a \tb\r\n"
        let parts = TextDiff.parts(original: text, proposed: text)
        XCTAssertEqual(DiffDemoFormatting.highlight(parts, showWhitespace: true).string, "a·⇥b↵\n")
        XCTAssertEqual(Array(DiffDemoFormatting.highlight(parts).string.utf16), Array(text.utf16))
    }
}
