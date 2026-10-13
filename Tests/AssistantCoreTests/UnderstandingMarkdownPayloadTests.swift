import XCTest
@testable import AssistantCore

final class UnderstandingMarkdownPayloadTests: XCTestCase {
    private let markdown = """
    ## Translation
    医用与**呼吸防护口罩**

    ## Notes
    - **Medical masks**：医用口罩，常指医用外科或一次性医用口罩。
    - **Respiratory masks**：呼吸防护口罩，强调颗粒物防护，如 N95/KN95。
    """

    func testTranslationCopiesPlainTextAndRetainsMarkdownNotes() throws {
        let result = try UnderstandingMarkdownPayload.parse(markdown)
        XCTAssertEqual(result.candidates, ["医用与呼吸防护口罩"])
        XCTAssertEqual(result.markdownCandidates, ["医用与**呼吸防护口罩**"])
        XCTAssertTrue(result.summary.contains("**Medical masks**"))
        XCTAssertTrue(result.explanations.isEmpty)
    }

    func testMissingDuplicateAndUnexpectedSectionsFailClosed() throws {
        let invalid = [
            markdown.replacingOccurrences(of: "## Notes", with: "## Details"),
            markdown + "\n## Notes\n- duplicate",
            markdown.replacingOccurrences(of: "## Translation\n医用与**呼吸防护口罩**\n\n", with: ""),
            "Preface\n" + markdown
        ]
        for value in invalid { XCTAssertThrowsError(try UnderstandingMarkdownPayload.parse(value)) }
    }
}
