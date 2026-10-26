import XCTest
import AssistantCore
@testable import EnglishCompass

@MainActor
final class WritingLanguagePreferenceTests: XCTestCase {
    func testDefaultPersistenceAndUnknownValueFallback() {
        let suite = "WritingLanguageTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.writingLanguage, .english)
        preferences.writeInstructions = "Keep product names."
        preferences.writingLanguage = .arabic
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.writingLanguage, .arabic)
        XCTAssertEqual(restored.writeInstructions, "Keep product names.")
        defaults.set("unsupported", forKey: "writingLanguage")
        XCTAssertEqual(Preferences(defaults: defaults).writingLanguage, .english)
    }
}
