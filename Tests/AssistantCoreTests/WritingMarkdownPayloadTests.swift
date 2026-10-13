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
        XCTAssertEqual(result.summary, "", "Summary stays optional for older-shaped responses")
    }

    func testSummarySectionIsParsedAndVersionLabelsAreStripped() throws {
        let withSummary = """
        ## General
        Look at the part my arrow points to.

        ## Conversational
        Check out where I'm pointing.

        ## Academic
        Please observe the indicated region.

        ## Notes
        - **General**: 自然中立的语气。
        - Conversational：使用 **"Check out"** 更口语。
        - 学术 - 用词正式精确。

        ## Summary
        原句结构完整，主要调整了**指示表达**。口语版更随意，学术版更正式。
        """
        let result = try WritingMarkdownPayload.parse(withSummary)
        XCTAssertEqual(result.summary, "原句结构完整，主要调整了**指示表达**。口语版更随意，学术版更正式。")
        XCTAssertEqual(result.explanations, ["自然中立的语气。", "使用 **\"Check out\"** 更口语。", "用词正式精确。"])
    }

    func testWritingPromptRequestsSummarySection() throws {
        let prompt = try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "")
        XCTAssertTrue(prompt.contains("## Summary"))
    }

    func testAsteriskBulletsAndHeadingVariantsAreAccepted() throws {
        let variant = """
        ### General
        greetings

        ## conversational
        hey

        ## Academic
        Greetings.

        ## Notes
        * 通用版本保留了原始输入。
        * 口语版本使用了更随意的 "hey"。
        1. 学术版本使用了更正式的 "Greetings"。
        """
        let result = try WritingMarkdownPayload.parse(variant)
        XCTAssertEqual(result.candidates, ["greetings", "hey", "Greetings."])
        XCTAssertEqual(result.explanations.count, 3)
    }

    func testMalformedSectionedMarkdownFailsInsteadOfBecomingOneAnswer() throws {
        let broken = "## General\ngreetings\n\n## Notes\n* only one note"
        let envelope = try JSONSerialization.data(withJSONObject: ["model": CloudAPIContract.model, "choices": [
            ["index": 0, "finish_reason": "stop", "message": ["content": broken]]]])
        XCTAssertThrowsError(try CloudAPIContract.parse(data: envelope, statusCode: 200, action: .writeEnglish))
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
