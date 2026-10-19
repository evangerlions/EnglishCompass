import XCTest
@testable import AssistantCore

final class QuestionAPIContractTests: XCTestCase {
    func testRequestPreservesContextHistoryAndMarkdownWithoutTransformationSchema() throws {
        let history = [QuestionMessage(role: .user, content: "Why use scrolling?"),
                       QuestionMessage(role: .assistant, content: "Use **inertial scrolling**."),
                       QuestionMessage(role: .user, content: "Give two examples.")]
        let request = try QuestionAPIContract.request(context: "Original: inertia scroll", messages: history,
                                                       key: "synthetic-test-key", model: "test-model")
        XCTAssertEqual(request.url, CloudAPIContract.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["enable_thinking"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 5)
        XCTAssertTrue(messages[0]["content"]!.contains("Markdown"))
        XCTAssertTrue(messages[1]["content"]!.contains("Original: inertia scroll"))
        XCTAssertEqual(Array(messages.dropFirst(2)).map { $0["content"]! }, history.map(\.content))
        XCTAssertEqual(messages[3]["role"], "assistant")
    }

    func testRejectsEmptyInvalidAndOversizedHistory() {
        XCTAssertThrowsError(try QuestionAPIContract.validate(context: "", messages: []))
        XCTAssertThrowsError(try QuestionAPIContract.validate(context: "", messages: [.init(role: .assistant, content: "Hi")]))
        XCTAssertThrowsError(try QuestionAPIContract.validate(context: "", messages: [.init(role: .user, content: "  ")]))
        XCTAssertThrowsError(try QuestionAPIContract.validate(context: String(repeating: "x", count: 32001),
            messages: [.init(role: .user, content: "Hi")]))
        XCTAssertThrowsError(try QuestionAPIContract.validate(context: "", messages:
            Array(repeating: .init(role: .user, content: "Hi"), count: 33)))
        XCTAssertThrowsError(try QuestionAPIContract.validate(context: String(repeating: "x", count: 32000), messages:
            [.init(role: .assistant, content: String(repeating: "x", count: 16000)), .init(role: .user, content: "Hi")]))
    }
}
