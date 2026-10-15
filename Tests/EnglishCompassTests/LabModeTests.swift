import XCTest
import AssistantCore
@testable import EnglishCompass

@MainActor
final class LabModeTests: XCTestCase {
    func testKeyComesOnlyFromEnvironmentAndIsTrimmed() {
        XCTAssertEqual(LabAppDelegate.environmentKey(["BAILIAN_API_KEY": "  sk-synthetic\n"]), "sk-synthetic")
        XCTAssertNil(LabAppDelegate.environmentKey([:]))
        XCTAssertNil(LabAppDelegate.environmentKey(["BAILIAN_API_KEY": "   "]))
        XCTAssertNil(LabAppDelegate.environmentKey(["BAILIAN_API_KEY": "sk-a\nsk-b"]))
    }

    func testMissingKeyFailsWithoutTouchingKeychain() async {
        var keychainRead = false
        let inference = InferenceService(credential: {
            // Lab passes a closure that never calls CloudCredentialStore.
            guard let key = LabAppDelegate.environmentKey([:]) else { throw AssistantFailure.cloudKeyMissing }
            keychainRead = true
            return key
        })
        do {
            _ = try await inference.infer(text: "Synthetic", action: .writeEnglish, additionalInstructions: "")
            XCTFail("Expected missing key")
        } catch {
            XCTAssertEqual(error as? AssistantFailure, .cloudKeyMissing)
        }
        XCTAssertFalse(keychainRead)
    }

    func testLabSettingsAreIsolatedFromTheInstalledApp() {
        let suite = LabAppDelegate.defaultsSuite
        let lab = UserDefaults(suiteName: suite)!
        defer { lab.removePersistentDomain(forName: suite) }
        XCTAssertNotEqual(suite, Bundle.main.bundleIdentifier)
        let preferences = Preferences(defaults: lab)
        preferences.writeInstructions = "Lab-only synthetic instruction"
        XCTAssertEqual(lab.string(forKey: "writeInstructions"), "Lab-only synthetic instruction")
        XCTAssertNotEqual(UserDefaults.standard.string(forKey: "writeInstructions"), "Lab-only synthetic instruction")
    }
}
