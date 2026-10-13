import XCTest
@testable import AssistantCore

final class WritingMarkdownPayloadTests: XCTestCase {
    private let markdown = """
    ## General
    Perform an **AX hit-test** at the mouse position.

    ## Conversational
    Do an **AX hit-test** where the mouse is.

    ## Academic
    Execute an `AX hit-test` at the current mouse coordinates.

    ## Notes
    - 通用版准确简洁。
    - 口语版更自然。
    - 学术版更正式。
    """

    func testFixedMarkdownSectionsProduceRichDisplayAndPlainCopyText() throws {
        let result = try WritingMarkdownPayload.parse(markdown)
        XCTAssertEqual(result.candidates, [
            "Perform an AX hit-test at the mouse position.",
            "Do an AX hit-test where the mouse is.",
            "Execute an AX hit-test at the current mouse coordinates."
        ])
        XCTAssertEqual(result.markdownCandidates[0], "Perform an **AX hit-test** at the mouse position.")
        XCTAssertEqual(result.explanations, ["通用版准确简洁。", "口语版更自然。", "学术版更正式。"])
    }

    func testMissingDuplicateOrExtraSectionsFailClosed() throws {
        let invalid = [
            markdown.replacingOccurrences(of: "## Notes", with: "## More"),
            markdown + "\n## Notes\n- duplicate",
            markdown.replacingOccurrences(of: "## Academic\nExecute an `AX hit-test` at the current mouse coordinates.\n\n", with: "")
        ]
        for value in invalid { XCTAssertThrowsError(try WritingMarkdownPayload.parse(value)) }
    }
}
