import XCTest
import AppKit
import AssistantCore
@testable import EnglishCompass

@MainActor private final class FakeInference: InferencePerforming {
    var requests = 0
    var cancellations = 0
    var delay: UInt64 = 0
    var failure: AssistantFailure?
    var receivedInstructions = ""
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult {
        requests += 1
        receivedInstructions = additionalInstructions
        // Intentionally return a late result even if cancellation was ignored upstream.
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        if let failure { throw failure }
        return ModelResult(candidates: [text])
    }
    func cancel() { cancellations += 1 }
}

final class SessionCancellationTests: XCTestCase {
    @MainActor func testPasteFillsInputWithoutRequestAndEmptyClipboardPreservesDraft() {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let session = subject(defaults, fake)
        let text = "  Synthetic draft.\nSecond line.  "
        pasteboard.setString(text, forType: .string)
        session.pasteInput(from: pasteboard)
        XCTAssertEqual(session.input, text)
        XCTAssertEqual(session.phase, .input)
        XCTAssertEqual(fake.requests, 0)
        XCTAssertFalse(session.hasCapturedTarget)
        pasteboard.clearContents()
        session.pasteInput(from: pasteboard)
        XCTAssertEqual(session.input, text)
        XCTAssertEqual(session.phase, .error)
        XCTAssertEqual(session.message, "Clipboard has no text.")
        XCTAssertEqual(fake.requests, 0)
    }
    @MainActor func testRequestTimingCompletesAndResetsForNewSession() async throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        fake.delay = 10_000_000
        let session = subject(defaults, fake)
        session.input = "Synthetic draft."
        session.process()
        XCTAssertNotNil(session.requestStartedAt)
        XCTAssertNil(session.elapsedSeconds)
        for _ in 0..<100 where session.phase == .processing { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(session.phase, .result)
        XCTAssertNil(session.requestStartedAt)
        XCTAssertGreaterThan(try XCTUnwrap(session.elapsedSeconds), 0)
        _ = session.begin(.understandEnglish, capture: false)
        XCTAssertNil(session.requestStartedAt)
        XCTAssertNil(session.elapsedSeconds)
    }
    @MainActor private func subject(_ defaults: UserDefaults, _ fake: FakeInference) -> AssistantSession {
        AssistantSession(preferences: Preferences(defaults: defaults),
                         accessibility: AccessibilityBridge(), inference: fake)
    }
    @MainActor func testQueuedRequestCannotStartAfterCancel() async throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = subject(defaults, fake)
        session.input = "Synthetic draft."
        session.process()
        session.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(fake.requests, 0)
        XCTAssertEqual(session.phase, .input)
    }
    @MainActor func testLateCancelledResultCannotApply() async throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        fake.delay = 50_000_000
        let session = subject(defaults, fake)
        session.input = "Synthetic draft."
        session.process()
        for _ in 0..<100 where fake.requests == 0 { await Task.yield() }
        XCTAssertEqual(fake.requests, 1)
        let count = fake.cancellations
        session.cancel()
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(session.phase, .input)
        XCTAssertNil(session.result)
        XCTAssertNil(session.elapsedSeconds)
        XCTAssertNil(session.requestStartedAt)
        XCTAssertEqual(fake.cancellations, count + 1)
    }
    @MainActor func testFailureDoesNotRetryOrReplaceDraft() async throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        fake.failure = .cloudUnavailable
        let session = subject(defaults, fake)
        session.preferences.additionalInstructions = "Use concise English."
        session.input = "Synthetic draft."
        session.process()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(fake.requests, 1)
        XCTAssertEqual(fake.receivedInstructions, "Use concise English.")
        XCTAssertEqual(session.phase, .error)
        XCTAssertNotNil(session.elapsedSeconds)
        XCTAssertNil(session.requestStartedAt)
        XCTAssertEqual(session.input, "Synthetic draft.")
    }
    @MainActor func testRetiredPreferencesAreRemovedWithoutLosingTermsOrShortcuts() throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("local", forKey: "provider")
        defaults.set("thinking", forKey: "writeMode")
        defaults.set("thinking", forKey: "understandMode")
        defaults.set("SyntheticTerm", forKey: "terms")
        let shortcut = Shortcut(keyCode: 1, modifiers: 6144, label: "Synthetic shortcut")
        defaults.set(try JSONEncoder().encode(shortcut), forKey: "writeShortcut")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.additionalInstructions, "Keep these terms unchanged: SyntheticTerm")
        XCTAssertNil(defaults.object(forKey: "terms"))
        preferences.additionalInstructions = "Use concise English.\nKeep a friendly tone."
        XCTAssertEqual(Preferences(defaults: defaults).additionalInstructions, preferences.additionalInstructions)
        XCTAssertEqual(preferences.writeShortcut, shortcut)
        for key in ["provider", "writeMode", "understandMode"] { XCTAssertNil(defaults.object(forKey: key)) }
    }
}
