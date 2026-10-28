import XCTest
@testable import AssistantCore

final class WritingMarkdownPayloadTests: XCTestCase {
    private let markdown = """
    ## General
    Please **help** me fix this bug.

    ## Direction
    更便于协作

    ## Alternative
    Please **help** me *resolve this issue*.

    ## Notes
    - Please 后使用动词原形。
    - 第二版优化措辞。

    ## Summary
    保持请求含义和语气。
    """

    func testTwoAnswersAndIndependentFreeFormDirection() throws {
        let result = try WritingMarkdownPayload.parse(markdown)
        XCTAssertEqual(result.candidates, ["Please help me fix this bug.", "Please help me resolve this issue."])
        XCTAssertEqual(result.revisionDirection, "更便于协作")
        XCTAssertEqual(result.markdownCandidates[1], "Please **help** me *resolve this issue*.")
        XCTAssertTrue(result.explanations.isEmpty)
        XCTAssertFalse(result.summary.contains("更便于协作"))
        XCTAssertTrue(result.summary.contains("## Notes"))
        XCTAssertTrue(result.summary.contains("## Summary"))
    }

    func testDirectionIsNotLimitedToPresetStrategies() throws {
        let content = markdown.replacingOccurrences(of: "更便于协作", with: "突出操作顺序")
        let result = try CloudAPIContract.parseContent(content, action: .writeEnglish)
        XCTAssertEqual(result.revisionDirection, "突出操作顺序")
        XCTAssertFalse(result.candidates.joined().contains("突出操作顺序"))
        let roundTrip = try JSONDecoder().decode(ModelResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(roundTrip, result)
    }

    func testMissingBlankMultilineOrDuplicateDirectionFailsClosed() {
        let invalid = [
            markdown.replacingOccurrences(of: "## Direction\n更便于协作\n\n", with: ""),
            markdown.replacingOccurrences(of: "更便于协作", with: " "),
            markdown.replacingOccurrences(of: "更便于协作", with: "更自然\n说明"),
            markdown.replacingOccurrences(of: "更便于协作", with: String(repeating: "长", count: 41)),
            markdown + "\n## Direction\n另一个方向"
        ]
        for content in invalid {
            XCTAssertThrowsError(try CloudAPIContract.parseContent(content, action: .writeEnglish))
        }
    }

    func testMissingOrDuplicateAnswerSectionsFailClosed() {
        let invalid = [
            markdown.replacingOccurrences(of: "## Alternative\nPlease **help** me *resolve this issue*.\n\n", with: ""),
            markdown + "\n## General\nDuplicate."
        ]
        for content in invalid { XCTAssertThrowsError(try WritingMarkdownPayload.parse(content)) }
    }

    func testMalformedSectionedMarkdownFailsInsteadOfBecomingOneAnswer() {
        XCTAssertThrowsError(try CloudAPIContract.parseContent("## General\nHello.\n## Notes\nA note.", action: .writeEnglish))
    }

    func testNotesAndSummaryAreOptionalAndFreeForm() throws {
        let answersOnly = String(markdown.components(separatedBy: "## Notes")[0])
        let result = try WritingMarkdownPayload.parse(answersOnly)
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertTrue(result.summary.isEmpty)
        let withNotes = answersOnly + "## Notes\n* first point  * second point"
        XCTAssertTrue(try WritingMarkdownPayload.parse(withNotes).summary.contains("second point"))
    }

    func testMultiLineAnswerKeepsEveryLineForDisplayAndCopy() throws {
        let content = """
        ## General
        Let's switch branches.
        1. Clean up test files.
        2. Switch to 47.5.0.
        ## Direction
        突出步骤
        ## Alternative
        Switch branches in this order:
        1. Clean up test files.
        2. Switch to 47.5.0.
        """
        let result = try WritingMarkdownPayload.parse(content)
        XCTAssertEqual(result.candidates[0], "Let's switch branches.\n1. Clean up test files.\n2. Switch to 47.5.0.")
        XCTAssertEqual(result.candidates.map { $0.components(separatedBy: "\n").count }, [3, 3])
    }

    func testHeadingVariantsAndOriginalSubheadingsArePreserved() throws {
        let content = markdown.replacingOccurrences(of: "## Alternative", with: "### alternative")
            .replacingOccurrences(of: "Please **help** me fix this bug.", with: "### Context\nPlease **help** me fix this bug.")
        let result = try WritingMarkdownPayload.parse(content)
        XCTAssertTrue(result.markdownCandidates[0].hasPrefix("### Context"))
        XCTAssertEqual(result.candidates.count, 2)
    }

    func testWritingPromptRequestsTwoAnswersAndFreeFormMetadata() throws {
        let prompt = try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "")
        XCTAssertTrue(prompt.contains("exactly two faithful English versions"))
        XCTAssertTrue(prompt.contains("## General, ## Direction, ## Alternative, ## Notes, ## Summary"))
        XCTAssertTrue(prompt.contains("Choose the label freely, not from a fixed list"))
        XCTAssertTrue(prompt.contains("exactly two Chinese bullet items"))
        XCTAssertFalse(prompt.contains("## Conversational"))
        XCTAssertFalse(prompt.contains("## Academic"))
    }

    func testWritingAlwaysTargetsEnglishIncludingChineseInput() throws {
        let request = try CloudAPIContract.request(text: "我是周凯你好", action: .writeEnglish,
                                                  additionalInstructions: "", key: "synthetic-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        let prompt = try XCTUnwrap(messages.first?["content"])
        XCTAssertTrue(prompt.contains("BOTH answer bodies is always English"))
        XCTAssertTrue(prompt.contains("never merely polish it in the source language"))
        XCTAssertTrue(prompt.contains("only if the input is already correct English"))
        XCTAssertTrue(prompt.contains("Direction, Notes and Summary remain in Chinese"))
        XCTAssertTrue(prompt.contains("General and Alternative MUST contain English answers"))
        XCTAssertTrue(prompt.contains("不能只润色原文"))
        XCTAssertEqual(messages.last?["content"], "我是周凯你好")
    }

    func testWritingPromptRequestsSelectiveEditEmphasis() throws {
        let prompt = try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "")
        XCTAssertTrue(prompt.contains("use **bold** only for corrections of errors such as grammar, spelling, tense or prepositions"))
        XCTAssertTrue(prompt.contains("use *italics* only for expression improvements where the original wording is valid"))
        XCTAssertTrue(prompt.contains("use bold only, not combined bold and italics"))
        XCTAssertTrue(prompt.contains("Do not label stylistic preferences or translation choices as errors"))
        XCTAssertTrue(prompt.contains("relative to the original input"))
        XCTAssertTrue(prompt.contains("Leave unchanged wording unmarked"))
        XCTAssertTrue(prompt.contains("never the entire answer"))
        XCTAssertTrue(prompt.contains("never insert them inside protected code"))
        XCTAssertTrue(prompt.contains("input 'Please helps me fix this bug.'"))
        XCTAssertTrue(prompt.contains("General: 'Please **help** me fix this bug.'"))
        XCTAssertTrue(prompt.contains("Alternative: 'Please **help** me *resolve this issue*.'"))
        XCTAssertTrue(prompt.contains("always use the selected target language for actual answers"))
    }
}
