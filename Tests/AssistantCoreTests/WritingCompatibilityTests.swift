import XCTest
@testable import AssistantCore

final class WritingCompatibilityTests: XCTestCase {
    private func parse(_ content: String, finish: String = "stop", calls: [[String: String]] = []) throws -> ModelResult {
        let data = try JSONSerialization.data(withJSONObject: ["model": CloudAPIContract.model, "choices": [
            ["index": 0, "finish_reason": finish, "message": ["content": content, "tool_calls": calls]]]])
        return try CloudAPIContract.parse(data: data, statusCode: 200, action: .writeEnglish)
    }

    func testSinglePlainTextAndJSONAnswersPreserveExactContent() throws {
        let text = "  I don't want inertial scrolling.\nKeep `scrollEnabled` unchanged.  "
        XCTAssertEqual(try parse(text), ModelResult(candidates: [text]))
        let data = try JSONSerialization.data(withJSONObject: ["candidates": [text]])
        XCTAssertEqual(try parse(String(decoding: data, as: UTF8.self)), ModelResult(candidates: [text]))
        XCTAssertEqual(try parse("{\"candidates\":[\"One answer\"],\"explanations\":[]}").candidates, ["One answer"])
    }

    func testSingleRichAnswerRetainsExplanationSummaryAndHighlights() throws {
        let expected = ModelResult(candidates: ["Disable inertial scrolling."], explanations: ["用于需求描述。"],
                                   summary: "强调禁用该效果。", highlights: [["inertial scrolling"]])
        let content = String(decoding: try JSONEncoder().encode(expected), as: UTF8.self)
        XCTAssertEqual(try parse(content), expected)
    }

    func testMalformedStructuredDataAndIncompleteResponsesNeverBecomePlainAnswers() throws {
        for content in ["", " \n", "{\"candidates\":[\"unfinished", "[]", "```json\n{}\n```",
                        "{\"candidates\":[]}", "{\"candidates\":[\"\"]}", "{\"candidates\":[\"ok\"],\"extra\":1}",
                        "{\"candidates\":[\"ok\"],\"explanations\":null}", "<think>reasoning</think>Answer"] {
            XCTAssertThrowsError(try parse(content), content)
        }
        XCTAssertThrowsError(try parse("One answer", finish: "length"))
        XCTAssertThrowsError(try parse("One answer", calls: [["name": "external_tool"]]))
    }
}
