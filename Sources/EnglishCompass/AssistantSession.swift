import AppKit
import SwiftUI
import AssistantCore

@MainActor
final class AssistantSession: ObservableObject {
    enum Phase: Equatable { case input, processing, result, error, replaced }
    @Published var phase: Phase = .input
    @Published var action: AssistantAction = .writeEnglish
    @Published var input = ""
    @Published var suggestion = ""
    @Published var result: ModelResult?
    @Published var candidateIndex: Int? = nil
    @Published var message = ""
    @Published var warnings: [String] = []
    @Published var rawResponse: String?
    @Published var rawRequest: String?
    @Published private(set) var elapsedSeconds: TimeInterval?
    @Published private(set) var requestStartedAt: Date?
    @Published private(set) var requestModel: QwenModel
    @Published private(set) var requestLanguage: WritingLanguage
    var actionTitle: String {
        action == .writeEnglish ? "Write in \((phase == .input ? preferences.writingLanguage : requestLanguage).name)" : action.title
    }
    @Published var sourceName = "Manual input"
    /// Measured scroll content and viewport of the current result view.
    struct ResultMeasure: Equatable { var content: CGFloat; var viewport: CGFloat }
    @Published var resultMeasure: ResultMeasure?
    @Published var inputMeasure: ResultMeasure?
    /// Set by the window fitter only after the result viewport reaches its cap.
    @Published var showsResultScrollIndicators = false
    @Published var isQuestionOpen = false
    @Published var questionUsesOverlay = false
    let questions: QuestionSession
    // Unlike .hidden, .never also suppresses macOS mouse-driven scrollers.
    var resultScrollIndicatorVisibility: ScrollIndicatorVisibility {
        showsResultScrollIndicators ? .automatic : .never
    }
    /// Partial Markdown while streaming; the result views render it live. Cleared
    /// when the finished payload is strictly parsed into `result`.
    @Published var streamingMarkdown: String?
    func reportResultMeasure(content: CGFloat, viewport: CGFloat) {
        let measure = ResultMeasure(content: content.rounded(), viewport: viewport.rounded())
        if measure != resultMeasure { resultMeasure = measure }
    }
    func reportInputMeasure(content: CGFloat, viewport: CGFloat) {
        let measure = ResultMeasure(content: content.rounded(), viewport: viewport.rounded())
        if measure != inputMeasure { inputMeasure = measure }
    }
    let preferences: Preferences
    var isAdjustingPanelHeight = false
    let accessibility: AccessibilityBridge
    let inference: any InferencePerforming
    let speech: SpeechService
    private var target: CapturedTarget?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    // Carried from a best-effort parse to the committed result (chooseCandidate
    // clears `message`), so a malformed-but-shown answer keeps its warning.
    private var pendingNotice: String?
    private var lastStreamed: String?
    private var lastStreamedNonEmpty: String? {
        lastStreamed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?

    init(preferences: Preferences, accessibility: AccessibilityBridge, inference: any InferencePerforming,
         speech: SpeechService? = nil) {
        self.preferences = preferences; self.accessibility = accessibility; self.inference = inference
        self.questions = QuestionSession(inference: inference)
        self.requestModel = preferences.model
        self.requestLanguage = preferences.writingLanguage
        self.speech = speech ?? SpeechService(preferences: preferences)
    }
    var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("--ui-test") }
    var hasCapturedTarget: Bool { target != nil }
    /// English text worth reading aloud in the current state: the highlighted
    /// answer for Write in English, the English source for Understand English.
    var speechText: String? {
        guard phase == .result else { return nil }
        let text = action == .writeEnglish ? suggestion : input
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
    var isStreaming: Bool { streamingMarkdown != nil }

    /// Select a streaming card; the partial text becomes the copy/speak target.
    func chooseStreamingCandidate(_ index: Int, plain: String) {
        guard isStreaming, liveWriteSections.cards.indices.contains(index),
              liveWriteSections.cards[index] != nil else { return }
        candidateIndex = index
        suggestion = plain
        message = ""
    }

    /// Default and copy target are updated on deltas, never during View.body.
    func refreshStreamingSelection() {
        guard action == .writeEnglish, isStreaming else { return }
        let cards = liveWriteSections.cards
        let index = candidateIndex ?? cards.firstIndex(where: { $0 != nil })
        guard let index, cards.indices.contains(index), let markdown = cards[index] else { return }
        if candidateIndex != index { candidateIndex = index }
        let plain = WritingMarkdownPayload.plainText(markdown)
        if suggestion != plain { suggestion = plain }
    }

    func speakCurrent() {
        guard let speechText else { return }
        speech.toggle(speechText, language: action == .writeEnglish ? requestLanguage : .english)
    }
    var canReplace: Bool {
        action == .writeEnglish && phase == .result && candidateIndex != nil && warnings.isEmpty &&
        !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        target.map { accessibility.canWrite($0) } == true
    }
    func begin(_ action: AssistantAction, capture: Bool = true, completion: @escaping (CGRect?) -> Void = { _ in }) {
        cancel(close: false)
        questions.reset()
        self.action = action
        phase = .input; input = ""; suggestion = ""; result = nil; candidateIndex = nil
        resultMeasure = nil; inputMeasure = nil; streamingMarkdown = nil
        warnings = []; message = ""; target = nil; sourceName = "Manual input"; rawResponse = nil; rawRequest = nil
        guard capture else {
            completion(nil)
            return
        }
        // Do not activate our panel until capture finishes. The Cmd+C fallback
        // must still be delivered to the source application.
        let id = requestID
        Task { [weak self] in
            guard let self, self.requestID == id else { return }
            do {
                let captured = try await self.accessibility.capture(action)
                guard self.requestID == id else { return }
                self.target = captured
                self.input = captured.snapshot.input
                self.sourceName = captured.app.localizedName ?? "Selected app"
                Diagnostics.event("text_read_success", action: action.rawValue)
                completion(captured.anchor)
                self.process()
            } catch {
                guard self.requestID == id else { return }
                self.message = error.localizedDescription
                self.phase = .error
                Diagnostics.event("text_read_unavailable", action: action.rawValue)
                completion(nil)
            }
        }
    }
    func pasteInput(from pasteboard: NSPasteboard = .general) {
        guard phase == .input || phase == .error else { return }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            message = "Clipboard has no text."
            phase = .error
            return
        }
        cancel(close: false)
        input = text
        target = nil; sourceName = "Manual input"
        result = nil; suggestion = ""; candidateIndex = nil
        message = ""; warnings = []; rawResponse = nil; rawRequest = nil
    }
    func process() {
        guard phase != .processing, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        closeQuestions()
        questions.reset()
        if let target, !input.utf16.elementsEqual(target.snapshot.input.utf16) {
            self.target = nil
            sourceName = "Manual input"
        }
        phase = .processing; message = ""; result = nil; candidateIndex = nil; warnings = []; rawResponse = nil
        lastStreamed = nil; pendingNotice = nil
        streamingMarkdown = ""
        elapsedSeconds = nil; requestStartedAt = Date()
        let id = UUID(); requestID = id
        requestLanguage = preferences.writingLanguage
        requestModel = preferences.model
        let model = requestModel
        let language = requestLanguage
        let text = input, action = action, additionalInstructions = preferences.instructions(for: action)
        Diagnostics.event("inference_started", action: action.rawValue, mode: "non-thinking")
        task = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, self.requestID == id else { return }
            let started = Date()
            self.inference.useModel(model)
            self.inference.useWritingLanguage(language)
            do {
                let result: ModelResult
                if self.isUITest {
                    try await Task.sleep(for: .seconds(1))
                    // Explicit UI fixture. Never reachable in a normal launch.
                    result = action == .writeEnglish ? WritingFixture.result : ModelResult(
                        candidates: ["请帮我修复这个问题。"], explanations: ["UI test fixture only; no model inference."])
                } else if self.inference.usesStreaming {
                    var buffer = ""
                    let content = try await self.inference.inferStream(
                        text: text, action: action, additionalInstructions: additionalInstructions
                    ) { [weak self] delta in
                        buffer += delta
                        guard let self, !Task.isCancelled, self.requestID == id else { return }
                        if self.phase == .processing { self.phase = .result }
                        self.streamingMarkdown = buffer
                        self.refreshStreamingSelection()
                        self.lastStreamed = buffer
                        self.rawRequest = self.inference.lastRawRequest
                        self.rawResponse = self.inference.lastRawResponse ?? buffer
                    }
                    self.lastStreamed = content
                    // Strict parse first. If the response is well formed use it;
                    // otherwise fall back to a best-effort result from whatever
                    // arrived, so a malformed answer is still shown/copyable
                    // instead of clearing the panel back to the input page.
                    if let parsed = try? CloudAPIContract.parseContent(content, action: action) {
                        result = parsed
                    } else {
                        // Malformed answer: keep it visible/copyable as best effort.
                        result = BestEffortResult.make(content: content, action: action)
                        self.pendingNotice = "The answer format was unexpected, so it is shown without the usual sections."
                    }
                } else {
                    result = try await self.inference.infer(text: text, action: action, additionalInstructions: additionalInstructions)
                }
                guard !Task.isCancelled, requestID == id else { return }
                elapsedSeconds = Date().timeIntervalSince(requestStartedAt ?? started)
                requestStartedAt = nil
                self.rawRequest = inference.lastRawRequest
                self.rawResponse = inference.lastRawResponse ?? lastStreamed
                self.resultMeasure = nil
                self.streamingMarkdown = nil
                self.result = result
                if action == .writeEnglish || result.candidates.count == 1 {
                    chooseCandidate(result.candidates.indices.contains(candidateIndex ?? -1) ? candidateIndex! : 0)
                }
                if let notice = self.pendingNotice { self.message = notice; self.pendingNotice = nil }
                phase = .result
                Diagnostics.event("inference_success", action: action.rawValue, mode: "stream")
                Diagnostics.metrics(elapsed: Date().timeIntervalSince(started), characters: text.count)
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                elapsedSeconds = Date().timeIntervalSince(requestStartedAt ?? started)
                requestStartedAt = nil
                self.rawRequest = inference.lastRawRequest
                // If anything streamed before the failure, keep it as a
                // best-effort result instead of dismissing to the error/input page.
                if let streamed = self.lastStreamedNonEmpty, !streamed.isEmpty {
                    let fallback = BestEffortResult.make(content: streamed, action: action)
                    self.rawResponse = inference.lastRawResponse ?? streamed
                    self.resultMeasure = nil
                    self.streamingMarkdown = nil
                    self.result = fallback
                    if action == .writeEnglish || fallback.candidates.count == 1 {
                        chooseCandidate(fallback.candidates.indices.contains(candidateIndex ?? -1) ? candidateIndex! : 0)
                    }
                    self.message = "The request ended unexpectedly; showing what was received."
                    phase = .result
                    return
                }
                self.rawResponse = inference.lastRawResponse
                phase = .error
                streamingMarkdown = nil
                if let debug = error as? InvalidResultError {
                    message = debug.errorDescription ?? "Error."
                    rawResponse = debug.rawResponse
                } else {
                    message = error.localizedDescription
                }
                Diagnostics.event("inference_failed", action: action.rawValue, mode: "non-thinking")
            }
        }
    }
    func chooseCandidate(_ index: Int) {
        guard let result, result.candidates.indices.contains(index) else { return }
        candidateIndex = index; suggestion = result.candidates[index]
        message = ""
        validateSuggestion()
    }
    func moveCandidate(_ offset: Int) {
        if isStreaming {
            let visible = liveWriteSections.cards.indices.filter { liveWriteSections.cards[$0] != nil }
            guard !visible.isEmpty else { return }
            let position = visible.firstIndex(of: candidateIndex ?? -1) ?? 0
            let index = visible[min(max(position + offset, 0), visible.count - 1)]
            chooseStreamingCandidate(index, plain: WritingMarkdownPayload.plainText(liveWriteSections.cards[index]!))
            return
        }
        guard phase == .result, action == .writeEnglish, let result else { return }
        chooseCandidate(min(max((candidateIndex ?? 0) + offset, 0), result.candidates.count - 1))
    }
    func validateSuggestion() {
        guard action == .writeEnglish else { warnings = []; return }
        let wasBlocked = !warnings.isEmpty
        warnings = ProtectionRules.check(source: target?.snapshot.input ?? input, candidate: suggestion, terms: []).warnings
        if !wasBlocked && !warnings.isEmpty { Diagnostics.event("protection_block", action: action.rawValue) }
    }
    func replace() {
        validateSuggestion()
        guard canReplace, let target else { return }
        do {
            try accessibility.replace(suggestion, in: target)
            phase = .replaced
            Diagnostics.event("writeback_success", action: action.rawValue)
            cancel()
        } catch {
            message = error.localizedDescription
            self.target = nil
            Diagnostics.event("writeback_blocked", action: action.rawValue)
        }
    }
    func copy(to pasteboard: NSPasteboard = .general) {
        guard phase == .result, candidateIndex != nil, !suggestion.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(suggestion, forType: .string)
        message = "Copied."
        Diagnostics.event("result_copied", action: action.rawValue)
    }
    func cancel(close: Bool = true) {
        closeQuestions()
        requestID = UUID(); task?.cancel(); task = nil
        if close { speech.stop() }
        if phase == .processing { inference.cancel() }
        if phase == .processing { Diagnostics.event("inference_cancelled", action: action.rawValue) }
        phase = .input
        requestStartedAt = nil; elapsedSeconds = nil
        if close {
            input = ""; suggestion = ""; result = nil; target = nil; warnings = []; rawResponse = nil; rawRequest = nil
            onClose?()
        }
    }
}
