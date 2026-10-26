import XCTest
@testable import AssistantCore

final class WritingLanguageTests: XCTestCase {
    func testCatalogAndAllTargetsReplaceThePromptPlaceholder() throws {
        XCTAssertEqual(Set(WritingLanguage.allCases.map(\.rawValue)),
                       ["en", "zh", "hi", "es", "ar", "fr", "bn", "pt", "id", "ur", "ja", "ko"])
        for language in WritingLanguage.allCases {
            let prompt = try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "", targetLanguage: language)
            XCTAssertTrue(prompt.contains("always \(language.name)"))
            XCTAssertTrue(prompt.contains("MUST contain \(language.name) answers"))
            XCTAssertTrue(prompt.contains(language.example))
            XCTAssertFalse(prompt.contains("{targetLanguage}"))
            if language != .english { XCTAssertFalse(prompt.contains("English")) }
            for stream in [false, true] {
                let request = try CloudAPIContract.request(text: "你好", action: .writeEnglish,
                    additionalInstructions: "", key: "synthetic", stream: stream, targetLanguage: language)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                XCTAssertEqual(messages[0]["content"], prompt)
                XCTAssertEqual(messages[1]["content"], "你好")
            }
        }
    }

    func testUnderstandIsIndependentAndEnglishRemainsDefault() throws {
        let standard = try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "")
        XCTAssertEqual(standard, try CloudAPIContract.prompt(action: .writeEnglish, additionalInstructions: "", targetLanguage: .english))
        let understand = try CloudAPIContract.prompt(action: .understandEnglish, additionalInstructions: "")
        for language in WritingLanguage.allCases {
            XCTAssertEqual(understand, try CloudAPIContract.prompt(action: .understandEnglish, additionalInstructions: "", targetLanguage: language))
        }
    }
}
