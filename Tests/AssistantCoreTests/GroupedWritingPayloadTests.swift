import XCTest
@testable import AssistantCore

final class GroupedWritingPayloadTests: XCTestCase {
    private let response = """
    ## General
    Please help me fix this bug.
    ## General Notes
    - **help**：使用动词原形。
    ## Direction
    更自然
    ## Alternative
    Please help me resolve this issue.
    ## Alternative Notes
    - **resolve this issue**：调整措辞。
    """

    func testEachAnswerOwnsItsExplanationAndCopyContainsOnlyBody() throws {
        let result = try CloudAPIContract.parseContent(response, action: .writeEnglish)
        XCTAssertEqual(result.candidates, ["Please help me fix this bug.", "Please help me resolve this issue."])
        XCTAssertEqual(result.explanations, ["- **help**：使用动词原形。", "- **resolve this issue**：调整措辞。"])
        XCTAssertEqual(result.usesPlainTextAnswers, true)
        XCTAssertTrue(result.summary.isEmpty)
        XCTAssertTrue(result.markdownCandidates.isEmpty)
        XCTAssertEqual(result.revisionDirection, "更自然")
        XCTAssertEqual(try JSONDecoder().decode(ModelResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testLiteralMarkupAndNewlinesAreNotStrippedFromBodies() throws {
        let literal = "Keep **literal** text, `code`, [link](https://example.com).\n\n1. One\n2. Two"
        let content = response.replacingOccurrences(of: "Please help me fix this bug.", with: literal)
        XCTAssertEqual(try WritingMarkdownPayload.parse(content).candidates[0], literal)
    }

    func testMissingExplanationRetainsItsOwnEmptySlot() throws {
        let content = response.replacingOccurrences(of: "## General Notes\n- **help**：使用动词原形。\n", with: "")
        let result = try WritingMarkdownPayload.parse(content)
        XCTAssertEqual(result.explanations[0], "")
        XCTAssertEqual(result.explanations[1], "- **resolve this issue**：调整措辞。")
    }

    func testDuplicateExplanationFailsInsteadOfContaminatingAnswers() {
        XCTAssertThrowsError(try WritingMarkdownPayload.parse(response + "\n## General Notes\nDuplicate"))
    }

    func testUnknownSubheadingStaysInsideAnswerOrExplanation() throws {
        let content = response.replacingOccurrences(of: "Please help me fix this bug.", with: "### Context\nPlease help me fix this bug.")
        let result = try WritingMarkdownPayload.parse(content)
        XCTAssertTrue(result.candidates[0].hasPrefix("### Context\n"))
        XCTAssertFalse(result.candidates[0].contains("使用动词原形"))
    }

    func testSplitNotesHeaderNeverLeaksIntoCopyableBody() {
        let heading = "## General Notes"
        for end in 1...heading.count {
            var sections = StreamingSections()
            sections.ingest("## General\nPlease help.\n" + String(heading.prefix(end)),
                            known: StreamingSections.writeHeadings)
            XCTAssertEqual(sections.displayOrNil("General"), "Please help.")
        }
    }

    func testScoredSingleReplyDoesNotRequireDirectionOrSecondReply() throws {
        for score in 0...10 {
            let content = "## Score\n\(score)\n## General\nKeep **literal** text.\n\nSecond line.\n## General Notes\n- 中文说明。"
            let result = try CloudAPIContract.parseContent(content, action: .writeEnglish)
            XCTAssertEqual(result.originalScore, score)
            XCTAssertEqual(result.candidates, ["Keep **literal** text.\n\nSecond line."])
            XCTAssertEqual(result.explanations, ["- 中文说明。"])
            XCTAssertNil(result.revisionDirection)
            XCTAssertEqual(result.usesPlainTextAnswers, true)
            XCTAssertEqual(try JSONDecoder().decode(ModelResult.self, from: JSONEncoder().encode(result)), result)
        }
    }

    func testFullScoreDoesNotForceRemovalOrRewriteOfModelAnswers() throws {
        let result = try WritingMarkdownPayload.parse("## Score\n10\n" + response)
        XCTAssertEqual(result.originalScore, 10)
        XCTAssertEqual(result.candidates, ["Please help me fix this bug.", "Please help me resolve this issue."])
        XCTAssertEqual(result.revisionDirection, "更自然")
    }

    func testUnscoredGroupedSingleReplyRemainsCompatible() throws {
        let result = try WritingMarkdownPayload.parse("## General\nHello.\n## General Notes\n无需修改。")
        XCTAssertNil(result.originalScore)
        XCTAssertEqual(result.candidates, ["Hello."])
        XCTAssertEqual(result.explanations, ["无需修改。"])
    }

    func testScoreWithMissingNotesStillUsesLiteralSingleReply() throws {
        let result = try WritingMarkdownPayload.parse("## Score\n9\n## General\nKeep **literal**.")
        XCTAssertEqual(result.candidates, ["Keep **literal**."])
        XCTAssertEqual(result.explanations, [""])
    }

    func testInvalidOrDuplicateScoreFailsWithoutEnteringAnswers() {
        for invalid in ["", "11", "-1", "7.5", "8/10", "8 points", "01", "八", "8\nextra"] {
            XCTAssertThrowsError(try WritingMarkdownPayload.parse("## Score\n\(invalid)\n" + response))
        }
        XCTAssertThrowsError(try WritingMarkdownPayload.parse("## Score\n8\n" + response + "\n## Score\n9"))
    }

    func testIncompleteOptionalGroupFailsStrictParsing() {
        let first = "## Score\n8\n## General\nHello.\n## General Notes\n说明。"
        for tail in ["\n## Direction\n更自然", "\n## Alternative\nHi.", "\n## Alternative Notes\n说明。", "\n## Direction\n更自然\n## Alternative\n"] {
            XCTAssertThrowsError(try WritingMarkdownPayload.parse(first + tail))
        }
    }

    func testStreamScoreWaitsForCompleteValueAndStaysSeparate() {
        var sections = StreamingSections()
        sections.ingest("## Score\n1", known: StreamingSections.writeHeadings)
        XCTAssertNil(sections.writeOriginalScore)
        sections.ingest("## Score\n10", known: StreamingSections.writeHeadings)
        XCTAssertNil(sections.writeOriginalScore)
        sections.ingest("## Score\n\n1", known: StreamingSections.writeHeadings)
        XCTAssertNil(sections.writeOriginalScore, "Leading blank lines must not commit a partial score")
        sections.ingest("## Score\n10\n", known: StreamingSections.writeHeadings)
        XCTAssertEqual(sections.writeOriginalScore, 10)
        sections.ingest("## Score\n10\n## General\nHello.\n## General Notes\n无需修改。", known: StreamingSections.writeHeadings)
        XCTAssertEqual(sections.writeOriginalScore, 10)
        XCTAssertEqual(sections.displayOrNil("General"), "Hello.")
        XCTAssertNil(sections.displayOrNil("Alternative"))
    }

    func testLegacyResultWithoutScoreDecodes() throws {
        let result = try WritingMarkdownPayload.parse(response)
        let encoded = try JSONEncoder().encode(result)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("originalScore"))
        XCTAssertNil(try JSONDecoder().decode(ModelResult.self, from: encoded).originalScore)
        XCTAssertThrowsError(try ModelResult(candidates: ["Hello."], originalScore: 11).validated())
        XCTAssertNoThrow(try ModelResult(candidates: ["Rewritten.", "Alternative."], originalScore: 10).validated())
    }

    func testIncrementalSectionsFinishEachBodyBeforeItsExplanation() {
        var sections = StreamingSections()
        let first = "## General\nPlease help.\n## General Notes\n- Explanation one."
        sections.ingest(first, known: StreamingSections.writeHeadings)
        XCTAssertEqual(sections.order, ["General", "General Notes"])
        XCTAssertEqual(sections.displayOrNil("General"), "Please help.")
        XCTAssertNil(sections.displayOrNil("Alternative"))
        sections.ingest(response, known: StreamingSections.writeHeadings)
        XCTAssertEqual(sections.order, WritingMarkdownPayload.groupedHeadings)
        XCTAssertEqual(sections.current, "Alternative Notes")
    }
}
