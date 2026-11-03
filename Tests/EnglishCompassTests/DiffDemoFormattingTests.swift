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

    @MainActor func testReviewShowsOnlyRevisedTextAndClickableChangeRanges() {
        let parts = TextDiff.parts(original: "She go home.", proposed: "She goes home.")
        let groups = DiffDemoChange.groups(parts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].before, "go")
        XCTAssertEqual(groups[0].after, "goes")
        let rich = DiffDemoReview.text(parts, selectedID: 0)
        XCTAssertEqual(rich.string, "She goes home.")
        XCTAssertEqual(rich.attribute(DiffDemoReview.changeID, at: 4, effectiveRange: nil) as? Int, 0)
        XCTAssertNil(rich.attribute(.strikethroughStyle, at: 4, effectiveRange: nil))
        XCTAssertNil(rich.attribute(DiffDemoReview.changeID, at: 0, effectiveRange: nil))
    }

    func testReviewKeepsPureDeletionAndInsertionGroups() {
        let deleted = DiffDemoChange.groups(TextDiff.parts(original: "very very fast", proposed: "very fast"))
        XCTAssertTrue(deleted.contains { $0.after.isEmpty && !$0.before.isEmpty && $0.proposedRange.length == 0 })
        let inserted = DiffDemoChange.groups(TextDiff.parts(original: "", proposed: "👩🏽‍💻\nnew"))
        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(inserted[0].before, "")
        XCTAssertEqual(inserted[0].after, "👩🏽‍💻\nnew")
        XCTAssertEqual(inserted[0].proposedRange.length, "👩🏽‍💻\nnew".utf16.count)
    }

    @MainActor func testReviewRangesStayValidAfterEmojiAndMultipleEdits() {
        let revised = "👩🏽‍💻 goes home!"
        let parts = TextDiff.parts(original: "👩🏽‍💻 go home.", proposed: revised)
        let groups = DiffDemoChange.groups(parts)
        XCTAssertEqual(groups.count, 2)
        let rich = DiffDemoReview.text(parts, selectedID: 1)
        XCTAssertEqual(Array(rich.string.utf16), Array(revised.utf16))
        for group in groups where group.proposedRange.length > 0 {
            XCTAssertEqual((revised as NSString).substring(with: group.proposedRange), group.after)
            XCTAssertEqual(rich.attribute(DiffDemoReview.changeID, at: group.proposedRange.location, effectiveRange: nil) as? Int, group.id)
        }
    }

    @MainActor func testLayeredDiffSeparatesReadingTextAndAnnotations() {
        let parts = TextDiff.parts(original: "She go home. Please helps.", proposed: "She goes home. Please help.")
        let view = DiffDemoLayeredDocument()
        view.setParts(parts, width: 500)
        XCTAssertEqual(view.revisedText, "She goes home. Please help.")
        XCTAssertEqual(view.annotations.map { $0.text.string }, ["go", "helps"])
        XCTAssertTrue(view.annotations.allSatisfy { $0.frame.maxY < $0.anchor.y })
        XCTAssertFalse(view.readingLines.isEmpty)
    }

    @MainActor func testLayeredNotesWrapWithoutCollidingWithTextOrEachOther() {
        let old = "a very long old phrase that should be completely visible near the end of the line"
        let parts = TextDiff.parts(original: old, proposed: "New.")
        let view = DiffDemoLayeredDocument()
        view.setParts(parts, width: 130)
        XCTAssertEqual(view.annotations.count, 1)
        XCTAssertGreaterThan(view.annotations[0].frame.height, 17)
        XCTAssertLessThanOrEqual(view.annotations[0].frame.maxX, 112)
        XCTAssertTrue(view.annotations[0].text.string.contains("completely"))
        XCTAssertLessThan(view.annotations[0].frame.maxY, view.readingLines[0].frame.minY)
        let dense = TextDiff.parts(original: "a b c d", proposed: "longword longerword longestword finalword")
        view.setParts(dense, width: 160)
        for (i, note) in view.annotations.enumerated() {
            for other in view.annotations.dropFirst(i + 1) {
                XCTAssertFalse(note.frame.intersects(other.frame))
            }
            XCTAssertTrue(view.readingLines.allSatisfy { !$0.frame.intersects(note.frame) })
        }
    }

    @MainActor func testLayeredPureDeletionEmptyTextAndResize() {
        let view = DiffDemoLayeredDocument()
        view.setParts(TextDiff.parts(original: "old\ntext", proposed: ""), width: 300)
        XCTAssertEqual(view.revisedText, "")
        XCTAssertEqual(view.annotations.count, 1)
        XCTAssertTrue(view.annotations[0].text.string.contains("↵"))
        XCTAssertGreaterThan(view.documentHeight, 0)
        view.setParts(TextDiff.parts(original: "", proposed: ""), width: 300)
        XCTAssertTrue(view.annotations.isEmpty)
        let text = String(repeating: "A sentence with 👩🏽‍💻 and spaces. ", count: 10)
        view.setParts(TextDiff.parts(original: text, proposed: text), width: 400)
        let wideCount = view.readingLines.count
        view.reflow(width: 150)
        XCTAssertGreaterThan(view.readingLines.count, wideCount)
        XCTAssertEqual(view.revisedText, text)
    }

    @MainActor func testLayeredSelectionCopiesOnlyRevisedTextAcrossLines() {
        let revised = "She goes home.\n\nPlease help me."
        let view = DiffDemoLayeredDocument()
        view.setParts(TextDiff.parts(original: "She go home.\n\nPlease helps me.", proposed: revised), width: 260)
        view.selectAll(nil)
        XCTAssertEqual(view.selectedText, revised)
        XCTAssertTrue(view.responds(to: #selector(NSText.copy(_:))))
        let range = (revised as NSString).range(of: "goes home.\n\nPlease help")
        view.select(from: NSMaxRange(range), to: range.location)
        XCTAssertEqual(view.selectedText, "goes home.\n\nPlease help")
        view.reflow(width: 150)
        XCTAssertEqual(view.selectedRange, range)
        XCTAssertEqual(view.selectedText, "goes home.\n\nPlease help")
    }

    @MainActor func testLayeredSelectionSnapsEmojiAndResetsForNewText() {
        let view = DiffDemoLayeredDocument()
        let revised = "👩🏽‍💻 goes home."
        view.setParts(TextDiff.parts(original: "👩🏽‍💻 go home.", proposed: revised), width: 300)
        view.select(from: 1, to: 2)
        XCTAssertEqual(view.selectedText, "👩🏽‍💻")
        view.setParts(TextDiff.parts(original: "old", proposed: "new"), width: 300)
        XCTAssertEqual(view.selectedRange.length, 0)
        XCTAssertEqual(view.selectedText, "")
        view.select(from: -100, to: 100)
        XCTAssertEqual(view.selectedText, "new")
    }

    @MainActor func testLayeredHitTestingIgnoresOldAnnotationsButAllowsCrossLineDragging() throws {
        let view = DiffDemoLayeredDocument()
        view.setParts(TextDiff.parts(original: "She go home.", proposed: "She goes home."), width: 300)
        let note = try XCTUnwrap(view.annotations.first)
        let point = NSPoint(x: note.frame.midX, y: note.frame.midY)
        XCTAssertNil(view.textOffset(at: point), "Old annotations are never selectable")
        XCTAssertNotNil(view.textOffset(at: point, dragging: true))
        let line = try XCTUnwrap(view.readingLines.first)
        XCTAssertEqual(view.textOffset(at: NSPoint(x: line.frame.minX, y: line.frame.midY)), 0)
    }

    @MainActor func testLayeredBodyRoutesNavigationKeysWithoutAffectingCopySelection() throws {
        let view = DiffDemoLayeredDocument()
        view.setParts(TextDiff.parts(original: "go", proposed: "goes"), width: 300)
        var routed: [UInt16] = []
        view.onNavigationKey = { routed.append($0); return true }
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125))
        view.keyDown(with: down)
        XCTAssertEqual(routed, [125])
        view.selectAll(nil)
        XCTAssertEqual(view.selectedText, "goes")
        XCTAssertEqual(view.selectedRange.length, 4)
    }

    @MainActor func testWhitespaceMarkersAreDisplayOnly() {
        let text = "a \tb\r\n"
        let parts = TextDiff.parts(original: text, proposed: text)
        XCTAssertEqual(DiffDemoFormatting.highlight(parts, showWhitespace: true).string, "a·⇥b↵\n")
        XCTAssertEqual(Array(DiffDemoFormatting.highlight(parts).string.utf16), Array(text.utf16))
    }
}
