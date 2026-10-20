import XCTest
import SwiftUI
@testable import EnglishCompass

final class JSONDebugHighlightTests: XCTestCase {
    func testJSONHasSwiftUIColorsForEveryTokenKind() {
        let value = JSONDebugView.highlight(#"{"key":"hello","count":12,"enabled":true,"missing":null}"#)
        let colors = Set(value.runs.compactMap { $0.foregroundColor })
        XCTAssertGreaterThanOrEqual(colors.count, 5)
        XCTAssertTrue(value.runs.allSatisfy { $0.foregroundColor != nil })
    }

    func testSSEIsColoredWithoutChangingWireText() {
        let wire = "data: {\"delta\":{\"content\":\"Hello 🌍\\n\\\"world\\\"\"},\"index\":0,\"finish_reason\":null}\r\n\r\ndata: [DONE]\r\n\r\n"
        let value = JSONDebugView.highlight(wire)
        XCTAssertEqual(String(value.characters), wire)
        XCTAssertGreaterThanOrEqual(Set(value.runs.compactMap { $0.foregroundColor }).count, 5)
    }

    func testIncompleteStreamAndPlainTextRemainReadable() {
        for raw in ["data: {\"content\":\"unfinished", "普通文本", "", "true", "123"] {
            let value = JSONDebugView.highlight(raw)
            XCTAssertEqual(String(value.characters), raw)
        }
    }
}
