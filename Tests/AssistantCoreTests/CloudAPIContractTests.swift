import XCTest
import Foundation
@testable import AssistantCore

final class CloudAPIContractTests: XCTestCase {
    private let key = "synthetic-secret-key"

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }

    private func completion(content: String? = nil, model: String = CloudAPIContract.model,
                            index: Any = 0, finish: Any = "stop", messageChanges: [String: Any] = [:]) throws -> Data {
        var message: [String: Any] = ["role": "assistant", "content": content ?? "{\"candidates\":[\"Hello\"],\"explanations\":[]}"]
        message.merge(messageChanges) { _, new in new }
        return try data(["model": model, "choices": [["index": index, "finish_reason": finish, "message": message]]])
    }

    private func expectFailure(_ failure: AssistantFailure, _ operation: () throws -> Any,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? AssistantFailure, failure, file: file, line: line)
            XCTAssertFalse(String(describing: error).contains("synthetic-secret-key"), file: file, line: line)
            XCTAssertFalse(error.localizedDescription.contains("private-provider-text"), file: file, line: line)
        }
    }

    func testRequestHasFixedEndpointModelAndNonThinkingJSONConfiguration() throws {
        let text = "  Please fix `my_code`.\nDo not send.  "
        let request = try CloudAPIContract.request(text: text, action: .writeEnglish, additionalInstructions: "Keep ZOOK unchanged.", key: key)
        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 120)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["model", "messages", "enable_thinking", "temperature", "max_tokens", "response_format", "stream"]))
        XCTAssertEqual(body["model"] as? String, "qwen3.7-flash")
        XCTAssertEqual(body["enable_thinking"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["temperature"] as? Double, 0.1)
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
        XCTAssertEqual(body["response_format"] as? [String: String], ["type": "text"])
        let understand = try CloudAPIContract.request(text: text, action: .understandEnglish,
                                                      additionalInstructions: "", key: key)
        let understandBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(understand.httpBody)) as? [String: Any])
        XCTAssertEqual(understandBody["response_format"] as? [String: String], ["type": "text"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1], ["role": "user", "content": text])
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(key))
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains(key))
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 3)
    }

    func testAdditionalInstructionsReachBothPromptsWithoutChangingInputOrSafetyContract() throws {
        let instructions = "Use concise English.\nKeep ZOOK unchanged.";
        for action in [AssistantAction.writeEnglish, .understandEnglish] {
            let request = try CloudAPIContract.request(text: "Synthetic input", action: action,
                                                      additionalInstructions: instructions, key: key)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let prompt = try XCTUnwrap(messages.first?["content"])
            XCTAssertTrue(prompt.hasSuffix(instructions))
            XCTAssertTrue(prompt.contains("only when compatible"))
            XCTAssertTrue(prompt.contains("Return only Markdown"))
            XCTAssertTrue(prompt.contains("Preserve negation"))
            XCTAssertFalse(prompt.contains("Protected terms:"))
            XCTAssertEqual(messages[1]["content"], "Synthetic input")
            let empty = try CloudAPIContract.request(text: "Synthetic input", action: action,
                                                     additionalInstructions: "", key: key)
            XCTAssertNotNil(empty.httpBody)
        }
    }

    func testRequestRejectsEmptyOversizedInputAndUnsafeCredentials() throws {
        for text in ["", " \n\t"] {
            expectFailure(.noText) { try CloudAPIContract.request(text: text, action: .writeEnglish, additionalInstructions: "", key: self.key) }
        }
        for text in [String(repeating: "x", count: 16001), String(repeating: "e\u{0301}", count: 8001)] {
            expectFailure(.contextLimit) { try CloudAPIContract.request(text: text, action: .writeEnglish, additionalInstructions: "", key: self.key) }
        }
        XCTAssertNoThrow(try CloudAPIContract.request(text: String(repeating: "x", count: 16000), action: .writeEnglish, additionalInstructions: "", key: key))
        for credential in ["", " \n"] {
            expectFailure(.cloudKeyMissing) { try CloudAPIContract.request(text: "Hello", action: .writeEnglish, additionalInstructions: "", key: credential) }
        }
        for credential in ["key\r\nInjected: bad", "a b", "中文", String(repeating: "a", count: 4097)] {
            expectFailure(.cloudAuth) { try CloudAPIContract.request(text: "Hello", action: .writeEnglish, additionalInstructions: "", key: credential) }
        }
    }

    func testParsesFinalContentOnlyAndNeverReturnsReasoningOrMetadata() throws {
        let response = try completion(messageChanges: ["reasoning_content": "private-provider-text synthetic-secret-key"])
        let result = try CloudAPIContract.parse(data: response, statusCode: 200)
        XCTAssertEqual(result, ModelResult(candidates: ["Hello"], explanations: []))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("private-provider-text"))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains(key))
    }

    func testStatusErrorsAreControlledWithoutReadingProviderErrorText() throws {
        let raw = Data("private-provider-text synthetic-secret-key malformed body".utf8)
        for (status, failure) in [(401, AssistantFailure.cloudAuth), (403, .cloudAuth), (429, .cloudRateLimit),
                                  (400, .cloudUnavailable), (500, .cloudUnavailable), (302, .cloudUnavailable), (204, .cloudUnavailable)] {
            expectFailure(failure) { try CloudAPIContract.parse(data: raw, statusCode: status) }
        }
        let error = try data(["error": ["message": "private-provider-text synthetic-secret-key"]])
        expectFailure(.invalidResult) { try CloudAPIContract.parse(data: error, statusCode: 200) }
    }

    func testEnvelopeRejectsIndexFinishAndToolCallsRegardlessOfEchoedModel() throws {
        // The compatible endpoint may echo any model id (multi-model support),
        // so a wrong/empty echoed model is NOT itself a rejection; index/finish
        // and tool-call shape still are.
        for index: Any in [true, false, -1, 1, "0", NSNull()] {
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.completion(index: index), statusCode: 200) }
        }
        for finish: Any in ["length", "tool_calls", "content_filter", NSNull()] {
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.completion(finish: finish), statusCode: 200) }
        }
        for changes: [String: Any] in [["tool_calls": [["name": "send"]]], ["tool_calls": "bad"],
                                       ["function_call": ["name": "send"]], ["content": NSNull()], ["content": 1]] {
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.completion(messageChanges: changes), statusCode: 200) }
        }
        for calls: Any in [NSNull(), [Any]()] {
            XCTAssertNoThrow(try CloudAPIContract.parse(data: completion(messageChanges: ["tool_calls": calls]), statusCode: 200))
        }
    }

    func testEnvelopeRequiresExactlyOneFullChoice() throws {
        let choice: [String: Any] = ["index": 0, "finish_reason": "stop", "message": ["content": "{}"]]
        for choices: Any in [[Any](), [choice, choice], "bad", [["index": 0, "delta": ["content": "{}"]]]] {
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.data(["model": CloudAPIContract.model, "choices": choices]), statusCode: 200) }
        }
        for raw in [Data(), Data("[".utf8), Data("[]".utf8), Data([0xff])] {
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: raw, statusCode: 200) }
        }
    }

    func testNormalizesOnlyBlankExplanationsAfterOriginalValidation() throws {
        for entries in [[""], ["", "term explanation"], [" \n\t", ""]] {
            let content = String(decoding: try data(["candidates": ["Hello"], "explanations": entries]), as: UTF8.self)
            let result = try CloudAPIContract.parse(data: completion(content: content), statusCode: 200)
            XCTAssertEqual(result.explanations, entries.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        for entries: Any in [["", "", ""], ["", NSNull()], [1], "", NSNull()] {
            let content = String(decoding: try data(["candidates": ["Hello"], "explanations": entries]), as: UTF8.self)
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.completion(content: content), statusCode: 200) }
        }
    }

    func testContentRejectsMalformedKeysCandidatesAndReasoningTags() throws {
        let invalid: [Any] = [
            ["candidates": [""], "explanations": []], ["candidates": [" \n"], "explanations": []],
            ["candidates": [], "explanations": []], ["candidates": ["a", "b", "c"], "explanations": []],
            ["candidates": [NSNull()], "explanations": []], ["candidates": [1], "explanations": []],
            ["candidates": ["Hello"]], ["explanations": []],
            ["candidates": ["Hello"], "explanations": [], "extra": "private-provider-text"],
            ["candidates": ["Keep <think>literal</think>"], "explanations": []],
            ["candidates": ["<think incomplete"], "explanations": []],
            ["candidates": ["Hello"], "explanations": ["</think>"]], []
        ]
        for value in invalid {
            let content = String(decoding: try data(value), as: UTF8.self)
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.completion(content: content), statusCode: 200) }
        }
        for content in ["not JSON", "{\"candidates\":[\"Hello\"", "```json\n{}\n```", "<think>private</think>{}"] {
            expectFailure(.invalidResult) { try CloudAPIContract.parse(data: self.completion(content: content), statusCode: 200) }
        }
        let markdown = "## Translation\n你好\n\n## Notes\n- **Hello**：常见问候语。"
        XCTAssertEqual(try CloudAPIContract.parse(data: completion(content: markdown), statusCode: 200,
                                                  action: .understandEnglish).candidates, ["你好"])
        let ambiguous = "{\"candidates\":[\"one\",\"two\"],\"explanations\":[]}"
        XCTAssertEqual(try CloudAPIContract.parse(data: completion(content: ambiguous), statusCode: 200).candidates, ["one", "two"])
    }

    func testAcceptsAnyEchoedModelIdForMultiModelSupport() throws {
        // Used for model benchmarking / future switching: the echo must not bind
        // the response to the single hard-coded model.
        for echoed in ["qwen3.6-flash", "deepseek-v4.1-flash", ""] {
            XCTAssertNoThrow(try CloudAPIContract.parse(data: completion(model: echoed), statusCode: 200))
        }
    }
}
