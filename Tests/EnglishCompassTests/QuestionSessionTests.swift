import XCTest
import AssistantCore
@testable import EnglishCompass

@MainActor
private final class QuestionInference: InferencePerforming {
    var history: [[QuestionMessage]] = []
    var contexts: [String] = []
    var model: QwenModel?
    var failure = false
    var pause = false
    var continuation: CheckedContinuation<String, Error>?
    var delta: (@MainActor (String) -> Void)?
    var cancelCount = 0
    func useModel(_ model: QwenModel) { self.model = model }
    func cancel() { cancelCount += 1 }
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult {
        ModelResult(candidates: ["Hello"])
    }
    func answerQuestion(context: String, messages: [QuestionMessage],
                        onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        history.append(messages); contexts.append(context); delta = onDelta
        if failure { throw AssistantFailure.cloudUnavailable }
        if pause { return try await withCheckedThrowingContinuation { continuation = $0 } }
        onDelta("## Example\n\n**Hello**")
        return "## Example\n\n**Hello**"
    }
}

final class QuestionSessionTests: XCTestCase {
    @MainActor private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Conversation did not settle")
    }

    @MainActor func testMultiTurnCarriesContextAndMarkdown() async throws {
        let inference = QuestionInference()
        let chat = QuestionSession(inference: inference)
        chat.configure(context: "Original and three answers", model: .flash37)
        chat.draft = "Explain this"; chat.send()
        try await settle { !chat.isSending }
        XCTAssertEqual(chat.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(chat.messages.last?.content, "## Example\n\n**Hello**")
        chat.draft = "Another example"; chat.send()
        try await settle { !chat.isSending }
        XCTAssertEqual(inference.history[1].count, 3)
        XCTAssertEqual(inference.history[1][1].content, "## Example\n\n**Hello**")
        XCTAssertEqual(inference.contexts, Array(repeating: "Original and three answers", count: 2))
        XCTAssertEqual(inference.model, .flash37)
        XCTAssertTrue(chat.error.isEmpty)
    }

    @MainActor func testFailureRestoresDraftForRetry() async throws {
        let inference = QuestionInference(); inference.failure = true
        let chat = QuestionSession(inference: inference)
        chat.draft = "Retry me"; chat.send()
        try await settle { !chat.isSending }
        XCTAssertEqual(chat.draft, "Retry me")
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertFalse(chat.error.isEmpty)
    }

    @MainActor func testStopIgnoresLateCallbacksAndResetClearsConversation() async throws {
        let inference = QuestionInference(); inference.pause = true
        let chat = QuestionSession(inference: inference)
        chat.configure(context: "reference", model: .flash37)
        chat.draft = "Explain"; chat.send()
        try await settle { inference.continuation != nil }
        inference.delta?("Partial")
        chat.stop()
        XCTAssertEqual(inference.cancelCount, 1)
        inference.delta?(" must not appear")
        inference.continuation?.resume(returning: "Late answer"); inference.continuation = nil
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(chat.messages.last?.content, "Partial")
        XCTAssertFalse(chat.isSending)
        chat.reset()
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertTrue(chat.context.isEmpty)
    }

    @MainActor func testBackPreservesInputAndResetsResultAndConversation() {
        let suite = "QuestionSessionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AssistantSession(preferences: Preferences(defaults: defaults),
            accessibility: AccessibilityBridge(), inference: QuestionInference())
        session.input = "Original input"
        session.phase = .result
        session.result = ModelResult(candidates: ["An answer"])
        session.chooseCandidate(0)
        session.openQuestions()
        XCTAssertTrue(session.isQuestionOpen)
        XCTAssertTrue(session.questions.context.contains("Original input"))
        XCTAssertTrue(session.questions.context.contains("An answer"))
        session.questions.draft = "Why?"
        session.returnToInput()
        XCTAssertEqual(session.phase, .input)
        XCTAssertEqual(session.input, "Original input")
        XCTAssertNil(session.result)
        XCTAssertNil(session.candidateIndex)
        XCTAssertFalse(session.isQuestionOpen)
        XCTAssertTrue(session.questions.context.isEmpty)
        XCTAssertTrue(session.questions.draft.isEmpty)
    }

    func testSidebarFitsWideScreensAndOverlaysNarrowScreens() {
        XCTAssertEqual(PanelSizing.windowWidth(questionOpen: true, screenWidth: 1440), 901)
        XCTAssertEqual(PanelSizing.windowWidth(questionOpen: false, screenWidth: 1440), 540)
        XCTAssertTrue(PanelSizing.questionUsesOverlay(screenWidth: 900))
        XCTAssertEqual(PanelSizing.windowWidth(questionOpen: true, screenWidth: 900), 540)
    }
}
