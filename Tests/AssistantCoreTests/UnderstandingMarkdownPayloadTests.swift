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

    func testTranslationPreservesParagraphsAndListLinesForDisplayAndCopy() throws {
        let content = """
        ## Translation
        # 换行测试

        这是第一段。

        ## 检查清单
        - 第一项
        - **第二项**

        最后一段。

        ## Notes
        - 说明
        """
        let result = try UnderstandingMarkdownPayload.parse(content)
        XCTAssertEqual(result.markdownCandidates.first, "# 换行测试\n\n这是第一段。\n\n## 检查清单\n- 第一项\n- **第二项**\n\n最后一段。")
        XCTAssertEqual(result.candidates.first, "# 换行测试\n\n这是第一段。\n\n## 检查清单\n- 第一项\n- 第二项\n\n最后一段。")
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
