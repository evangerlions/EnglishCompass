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
    var lastRawRequest: String?
    var lastRawResponse: String?
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
    @MainActor func testSuccessfulNonStreamingResultKeepsRawRequestAndResponse() async throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        fake.lastRawRequest = "{\"stream\":false}"
        fake.lastRawResponse = "{\"choices\":[{\"message\":{\"content\":\"Hello.\"}}]}"
        let session = subject(defaults, fake)
        session.input = "Hello."
        session.process()
        for _ in 0..<100 where session.requestStartedAt != nil {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(session.phase, .result)
        XCTAssertEqual(session.rawRequest, fake.lastRawRequest)
        XCTAssertEqual(session.rawResponse, fake.lastRawResponse)
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
        session.begin(.understandEnglish, capture: false)
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
        session.preferences.writeInstructions = "Use concise English."
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
        XCTAssertEqual(preferences.writeInstructions, "Keep these terms unchanged: SyntheticTerm")
        XCTAssertEqual(preferences.understandInstructions, "Keep these terms unchanged: SyntheticTerm")
        XCTAssertNil(defaults.object(forKey: "terms"))
        preferences.writeInstructions = "Use concise English.\nKeep a friendly tone."
        preferences.understandInstructions = "Explain terms in Chinese."
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.writeInstructions, preferences.writeInstructions)
        XCTAssertEqual(reloaded.understandInstructions, preferences.understandInstructions)
        XCTAssertNotEqual(reloaded.writeInstructions, reloaded.understandInstructions)
        XCTAssertEqual(preferences.writeShortcut, shortcut)
        for key in ["provider", "writeMode", "understandMode"] { XCTAssertNil(defaults.object(forKey: key)) }
    }
    @MainActor func testLegacySharedInstructionsMigrateToBothActionsOnce() {
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("Legacy shared preference", forKey: "additionalInstructions")
        let migrated = Preferences(defaults: defaults)
        XCTAssertEqual(migrated.writeInstructions, "Legacy shared preference")
        XCTAssertEqual(migrated.understandInstructions, "Legacy shared preference")
        XCTAssertNil(defaults.object(forKey: "additionalInstructions"))
        migrated.writeInstructions = "Write only"
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.writeInstructions, "Write only")
        XCTAssertEqual(reloaded.understandInstructions, "Legacy shared preference")
    }
    @MainActor func testEachActionUsesOnlyItsOwnInstructions() async throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = subject(defaults, fake)
        session.preferences.writeInstructions = "Write-specific preference"
        session.preferences.understandInstructions = "Understand-specific preference"
        session.action = .understandEnglish
        session.input = "Synthetic text"
        session.process()
        for _ in 0..<100 where fake.requests == 0 { await Task.yield() }
        XCTAssertEqual(fake.receivedInstructions, "Understand-specific preference")
        session.cancel(close: false)
        session.action = .writeEnglish
        session.input = "Synthetic text"
        session.process()
        for _ in 0..<100 where fake.requests < 2 { await Task.yield() }
        XCTAssertEqual(fake.receivedInstructions, "Write-specific preference")
    }
    @MainActor func testUnderstandShortcutDefaultsToRAndMigratesOldDefaultOnly() throws {
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(Preferences(defaults: defaults).understandShortcut, .understand)
        XCTAssertEqual(Shortcut.understand.keyCode, 15)
        defaults.set(try JSONEncoder().encode(Shortcut.legacyUnderstand), forKey: "understandShortcut")
        XCTAssertEqual(Preferences(defaults: defaults).understandShortcut, .understand)
        let custom = Shortcut(keyCode: 2, modifiers: 6144, label: "Control + Option + D")
        defaults.set(try JSONEncoder().encode(custom), forKey: "understandShortcut")
        XCTAssertEqual(Preferences(defaults: defaults).understandShortcut, custom)
    }
    @MainActor func testSpeechPreferencesDefaultPersistAndClamp() {
        let name = "EnglishCompassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let fresh = Preferences(defaults: defaults)
        XCTAssertEqual(fresh.speakShortcut, .speak)
        XCTAssertEqual(fresh.speechAccent, "en-US")
        XCTAssertEqual(fresh.speechVoice, "")
        XCTAssertEqual(fresh.speechRate, Preferences.defaultSpeechRate)
        fresh.speechAccent = "en-GB"; fresh.speechRate = 0.55
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.speechAccent, "en-GB")
        XCTAssertEqual(reloaded.speechRate, 0.55, accuracy: 0.0001)
        defaults.set(5.0, forKey: "speechRate"); defaults.set("fr-FR", forKey: "speechAccent")
        let sanitized = Preferences(defaults: defaults)
        XCTAssertEqual(sanitized.speechRate, 0.60, accuracy: 0.0001)
        XCTAssertEqual(sanitized.speechAccent, "en-US")
    }
    @MainActor func testDefaultShortcutsAreDistinctAndConflictsAreRejected() throws {
        let defaultsSet = ShortcutKind.allCases.map(\.defaultShortcut)
        XCTAssertEqual(Set(defaultsSet.map { "\($0.keyCode)-\($0.modifiers)" }).count, ShortcutKind.allCases.count)
        let shortcuts = GlobalShortcuts()
        XCTAssertThrowsError(try shortcuts.register([.write: .write, .understand: .understand, .speak: .write]))
    }
    @MainActor func testSpeechTextFollowsActionAndPhase() {
        let name = "EnglishCompassTests.\(UUID().uuidString)", fake = FakeInference()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = subject(defaults, fake)
        session.input = "Synthetic source."
        XCTAssertNil(session.speechText, "Nothing to read before a result exists")
        session.result = ModelResult(candidates: ["First answer.", "Second answer.", "Third answer."])
        session.phase = .result
        session.chooseCandidate(1)
        XCTAssertEqual(session.speechText, "Second answer.")
        session.action = .understandEnglish
        XCTAssertEqual(session.speechText, "Synthetic source.")
    }
}
