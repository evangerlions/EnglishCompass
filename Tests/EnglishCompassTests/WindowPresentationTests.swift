import AppKit
import XCTest
import AssistantCore
@testable import EnglishCompass

@MainActor private final class ReopenInference: InferencePerforming {
    var requests = 0
    var cancellations = 0
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult {
        requests += 1
        return ModelResult(candidates: ["A test answer"])
    }
    func cancel() { cancellations += 1 }
}

final class WindowPresentationTests: XCTestCase {
    @MainActor func testPanelAndLabDoNotHideOnDeactivate() {
        let rect = NSRect(x: 200, y: 200, width: 540, height: 300)
        let panel = NSPanel(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let lab = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; lab.isReleasedWhenClosed = false
        defer { panel.close(); lab.close() }
        AssistantWindowPresentation.configure(panel)
        AssistantWindowPresentation.configure(lab)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(lab.hidesOnDeactivate)
        panel.orderFront(nil)
        panel.resignKey()
        XCTAssertTrue(panel.isVisible, "Losing keyboard focus must not dismiss the panel")
        panel.orderOut(nil)
        XCTAssertFalse(panel.isVisible, "Explicit close/hide remains possible")
    }

    @MainActor func testReopenRestoresHiddenWindowWithoutResettingSession() {
        let suite = "WindowPresentationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let inference = ReopenInference()
        let session = AssistantSession(preferences: Preferences(defaults: defaults),
                                       accessibility: AccessibilityBridge(), inference: inference)
        session.input = "Original draft"
        session.phase = .result
        session.result = ModelResult(candidates: ["A test answer"])
        session.chooseCandidate(0)
        session.rawRequest = "request"; session.rawResponse = "response"
        session.openQuestions(); session.questions.draft = "Why?"
        let context = session.questions.context
        let window = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 540, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        AssistantWindowPresentation.configure(window)
        window.orderOut(nil)
        AssistantWindowPresentation.restore(window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(session.input, "Original draft")
        XCTAssertEqual(session.result?.candidates, ["A test answer"])
        XCTAssertEqual(session.candidateIndex, 0)
        XCTAssertEqual(session.rawResponse, "response")
        XCTAssertEqual(session.rawRequest, "request")
        XCTAssertTrue(session.isQuestionOpen)
        XCTAssertEqual(session.questions.draft, "Why?")
        XCTAssertEqual(session.questions.context, context)
        XCTAssertEqual(inference.requests, 0)
        XCTAssertEqual(inference.cancellations, 0)
    }

    @MainActor func testRestoreDoesNotChangeWindowGeometry() {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 540, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let frame = window.frame
        AssistantWindowPresentation.restore(window)
        XCTAssertEqual(window.frame, frame)
        XCTAssertTrue(window.isVisible)
    }

    @MainActor func testPackagedReleaseUsesDockAndLabHasSeparateIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["LSUIElement"] as? Bool, false)
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertNotEqual(plist["CFBundleIdentifier"] as? String, LabAppDelegate.defaultsSuite)
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/build-lab.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("com.zook.EnglishCompass.lab"))
        XCTAssertTrue(script.contains("AppIcon-imagegen-v2.icns"))
        XCTAssertFalse(script.contains("/Applications/"))
        XCTAssertFalse(script.contains("BAILIAN_API_KEY"))
    }
}
