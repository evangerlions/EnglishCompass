import Foundation
import XCTest
@testable import EnglishCompass

final class SelectionCaptureTests: XCTestCase {
    @MainActor func testPartialSelectionDoesNotCaptureSurroundingLines() throws {
        let selected = "this is the common I want transition"
        let full = "这个是语句 a\n这个是语句 b\n" + selected
        let range = (full as NSString).range(of: selected)
        let captured = try AccessibilityBridge.selectionSnapshot(
            selectedText: selected, fullText: full, selectedRange: range)

        XCTAssertEqual(captured.snapshot.input, selected)
        XCTAssertEqual(captured.snapshot.range, range)
        XCTAssertEqual(captured.snapshot.fullText, full)
        XCTAssertTrue(captured.writebackEligible)
    }

    @MainActor func testMissingRangeKeepsOnlySelectedText() throws {
        let captured = try AccessibilityBridge.selectionSnapshot(
            selectedText: "last line", fullText: "first line\nlast line", selectedRange: nil)

        XCTAssertEqual(captured.snapshot.input, "last line")
        XCTAssertEqual(captured.snapshot.fullText, "last line")
        XCTAssertFalse(captured.writebackEligible)
    }

    @MainActor func testInvalidOrMismatchedRangeNeverFallsBackToWholeField() throws {
        let full = "prefix selected suffix"
        let ranges = [
            NSRange(location: 0, length: 6),
            NSRange(location: 7, length: 0),
            NSRange(location: NSNotFound, length: 8),
            NSRange(location: 7, length: Int.max)
        ]
        for range in ranges {
            let captured = try AccessibilityBridge.selectionSnapshot(
                selectedText: "selected", fullText: full, selectedRange: range)
            XCTAssertEqual(captured.snapshot.input, "selected")
            XCTAssertEqual(captured.snapshot.fullText, "selected")
            XCTAssertFalse(captured.writebackEligible)
        }
    }

    @MainActor func testReadOnlySelectionRetainsWhitespaceAndLineBreaks() throws {
        let selected = "  first\n\nsecond  "
        let captured = try AccessibilityBridge.selectionSnapshot(
            selectedText: selected, fullText: nil, selectedRange: nil)

        XCTAssertEqual(captured.snapshot.input, selected)
        XCTAssertFalse(captured.writebackEligible)
    }

    @MainActor func testUTF16RangeIdentifiesCorrectOccurrence() throws {
        let full = "🌍 same\nsame"
        let range = (full as NSString).range(of: "same", options: .backwards)
        let captured = try AccessibilityBridge.selectionSnapshot(
            selectedText: "same", fullText: full, selectedRange: range)

        XCTAssertEqual(captured.snapshot.input, "same")
        XCTAssertEqual(captured.snapshot.range, range)
        XCTAssertTrue(captured.writebackEligible)
    }

    @MainActor func testFullSelectionStillUsesItsExactRange() throws {
        let full = "one\ntwo"
        let range = NSRange(location: 0, length: full.utf16.count)
        let captured = try AccessibilityBridge.selectionSnapshot(
            selectedText: full, fullText: full, selectedRange: range)

        XCTAssertEqual(captured.snapshot.input, full)
        XCTAssertEqual(captured.snapshot.range, range)
        XCTAssertTrue(captured.writebackEligible)
    }

    @MainActor func testEmptySelectionIsNotReplacedByFieldValue() {
        XCTAssertThrowsError(try AccessibilityBridge.selectionSnapshot(
            selectedText: " \n", fullText: "whole field", selectedRange: nil))
    }
}
