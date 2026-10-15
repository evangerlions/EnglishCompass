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
        // Notes are free-form body content, not per-card copy data.
        XCTAssertTrue(result.explanations.isEmpty)
        XCTAssertTrue(result.summary.contains("## Notes"))
        XCTAssertTrue(result.summary.contains("通用版准确简洁。"))
    }

    func testSummaryAndNotesAreBothKeptAsBody() throws {
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
        XCTAssertEqual(result.candidates.count, 3)
        XCTAssertTrue(result.summary.contains("## Notes"))
        XCTAssertTrue(result.summary.contains("使用 **\"Check out\"** 更口语。"))
        XCTAssertTrue(result.summary.contains("## Summary"))
        XCTAssertTrue(result.summary.contains("主要调整了**指示表达**"))
    }

    func testWritingPromptRequestsSummarySection() throws {
        let prompt = try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "")
        XCTAssertTrue(prompt.contains("## Summary"))
    }

    func testMultiLineAnswerKeepsEveryLineForDisplayAndCopy() throws {
        let response = """
        ## General
        Now let's switch branches.
        1. Delete unused test files first.
        2. Switch to the latest code of branch 47.5.0.

        ## Conversational
        Let's switch branches now.
        First, clean up the test files.
        Then switch to 47.5.0.

        ## Academic
        Proceed with the branch switch.
        Remove obsolete test artifacts.
        Update to branch 47.5.0.

        ## Notes
        - a
        - b
        - c
        """
        let result = try WritingMarkdownPayload.parse(response)
        XCTAssertEqual(result.candidates[0], "Now let's switch branches.\n1. Delete unused test files first.\n2. Switch to the latest code of branch 47.5.0.")
        XCTAssertEqual(result.candidates.map { $0.components(separatedBy: "\n").count }, [3, 3, 3])
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
        XCTAssertTrue(result.summary.contains("通用版本保留了原始输入。"))
    }

    func testMalformedSectionedMarkdownFailsInsteadOfBecomingOneAnswer() throws {
        // Missing two required answer sections must fail.
        let broken = "## General\ngreetings\n\n## Notes\n* only one note"
        let envelope = try JSONSerialization.data(withJSONObject: ["model": CloudAPIContract.model, "choices": [
            ["index": 0, "finish_reason": "stop", "message": ["content": broken]]]])
        XCTAssertThrowsError(try CloudAPIContract.parse(data: envelope, statusCode: 200, action: .writeEnglish))
    }

    func testNotesEmittedOnOnePhysicalLineDoNotBreakAcceptance() throws {
        // Notes shape is irrelevant to acceptance; only the three answers matter.
        let body = """
        ## General
        one

        ## Conversational
        two

        ## Academic
        three

        ## Notes
        * first point here  * second one here  * third one here

        ## Summary
        A short summary sentence.
        """
        let result = try WritingMarkdownPayload.parse(body)
        XCTAssertEqual(result.candidates, ["one", "two", "three"])
        XCTAssertTrue(result.summary.contains("first point here"))
    }

    func testAnswerWithNoBodyStillAccepted() throws {
        // No Notes/Summary at all: the three answers alone are enough.
        let body = """
        ## General
        one

        ## Conversational
        two

        ## Academic
        three
        """
        let result = try WritingMarkdownPayload.parse(body)
        XCTAssertEqual(result.candidates, ["one", "two", "three"])
        XCTAssertTrue(result.summary.isEmpty)
    }

    func testMissingOrDuplicateAnswerSectionsFailClosed() throws {
        let invalid = [
            markdown.replacingOccurrences(of: "## Academic\nExecute an `AX hit-test` at the current mouse coordinates.\n\n", with: ""),
            markdown + "\n## General\n- duplicate answer"
        ]
        for value in invalid { XCTAssertThrowsError(try WritingMarkdownPayload.parse(value)) }
    }
}
