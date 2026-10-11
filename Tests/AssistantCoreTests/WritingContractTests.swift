import XCTest
@testable import AssistantCore

final class WritingContractTests: XCTestCase {
    private func envelope(_ result: ModelResult) throws -> Data {
        let content = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["model": CloudAPIContract.model, "choices": [
            ["index": 0, "finish_reason": "stop", "message": ["content": content]]]])
    }
    private var valid: ModelResult {
        ModelResult(candidates: ["Neutral answer.", "Casual answer.", "Formal answer."],
                    explanations: ["说明一", "说明二", "说明三"], summary: "整体说明。",
                    highlights: [["Neutral"], [], ["Formal"]])
    }
    func testThreeOrderedAnswersAndEmphasisArePlainText() throws {
        let parsed = try CloudAPIContract.parse(data: envelope(valid), statusCode: 200, action: .writeEnglish)
        XCTAssertEqual(parsed, valid)
        XCTAssertThrowsError(try CloudAPIContract.parse(data: envelope(valid), statusCode: 200, action: .understandEnglish))
        XCTAssertEqual(try CloudAPIContract.parse(data: envelope(ModelResult(candidates: ["Old answer"])),
                                                  statusCode: 200, action: .writeEnglish).candidates, ["Old answer"])
    }
    func testIncompleteExplanationSummaryOrInvalidHighlightsFailClosed() throws {
        var fixtures: [ModelResult] = []
        var result = valid; result.summary = " "; fixtures.append(result)
        result = valid; result.explanations = ["one", "two"]; fixtures.append(result)
        result = valid; result.explanations[0] = " "; fixtures.append(result)
        result = valid; result.highlights = []; fixtures.append(result)
        result = valid; result.highlights[0] = ["not in answer"]; fixtures.append(result)
        result = valid; result.highlights[0] = [""]; fixtures.append(result)
        result = valid; result.summary = "<think>hidden"; fixtures.append(result)
        for fixture in fixtures {
            XCTAssertThrowsError(try CloudAPIContract.parse(data: envelope(fixture), statusCode: 200, action: .writeEnglish))
        }
    }
    func testSinglePhraseHighlightShapeNormalizesWithoutChangingAnswer() throws {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as! [String: Any]
        value["highlights"] = ["Neutral", "", "Formal"]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: ["model": CloudAPIContract.model, "choices": [
            ["index": 0, "finish_reason": "stop", "message": ["content": content]]]])
        XCTAssertEqual(try CloudAPIContract.parse(data: data, statusCode: 200, action: .writeEnglish), valid)
    }
}
