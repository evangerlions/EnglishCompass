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
    @Published var sourceName = "Manual input"
    /// Measured scroll content and viewport of the current result view.
    struct ResultMeasure: Equatable { var content: CGFloat; var viewport: CGFloat }
    @Published var resultMeasure: ResultMeasure?
    @Published var inputMeasure: ResultMeasure?
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
    let accessibility: AccessibilityBridge
    let inference: any InferencePerforming
    let speech: SpeechService
    private var target: CapturedTarget?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?

    init(preferences: Preferences, accessibility: AccessibilityBridge, inference: any InferencePerforming,
         speech: SpeechService? = nil) {
        self.preferences = preferences; self.accessibility = accessibility; self.inference = inference
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

    /// Live per-section Markdown for the Write response while streaming.
    /// Index order matches the three cards; nil means that card has not started.
    var liveWriteSections: (cards: [String?], notes: String?, summary: String?) {
        guard let md = streamingMarkdown else { return (Array(repeating: nil, count: 3), nil, nil) }
        var s = StreamingSections()
        s.ingest(md, known: StreamingSections.writeHeadings)
        return ([s.displayOrNil("General"), s.displayOrNil("Conversational"), s.displayOrNil("Academic")],
                s.displayOrNil("Notes"), s.displayOrNil("Summary"))
    }

    /// Live sections for the Understand response while streaming.
    var liveUnderstandSections: (translation: String?, notes: String?) {
        guard let md = streamingMarkdown else { return (nil, nil) }
        var s = StreamingSections()
        s.ingest(md, known: StreamingSections.understandHeadings)
        return (s.displayOrNil("Translation"), s.displayOrNil("Notes"))
    }

    func speakCurrent() {
        guard let speechText else { return }
        speech.toggle(speechText)
    }
    var canReplace: Bool {
        action == .writeEnglish && phase == .result && candidateIndex != nil && warnings.isEmpty &&
        !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        target.map { accessibility.canWrite($0) } == true
    }
    func begin(_ action: AssistantAction, capture: Bool = true, completion: @escaping (CGRect?) -> Void = { _ in }) {
        cancel(close: false)
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
        if let target, !input.utf16.elementsEqual(target.snapshot.input.utf16) {
            self.target = nil
            sourceName = "Manual input"
        }
        phase = .processing; message = ""; result = nil; candidateIndex = nil; warnings = []; rawResponse = nil
        streamingMarkdown = ""
        elapsedSeconds = nil; requestStartedAt = Date()
        let id = UUID(); requestID = id
        let text = input, action = action, additionalInstructions = preferences.instructions(for: action)
        Diagnostics.event("inference_started", action: action.rawValue, mode: "non-thinking")
        task = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, self.requestID == id else { return }
            let started = Date()
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
                        // Switch to the result surface immediately so the first
                        // section can render while the rest keeps streaming.
                        guard let self else { return }
                        if self.phase == .processing { self.phase = .result }
                        self.streamingMarkdown = buffer
                    }
                    // Streaming joined deltas are content only (no response
                    // envelope); parse them with the content parser, which only
                    // requires the three copy-ready answers.
                    result = try CloudAPIContract.parseContent(content, action: action)
                } else {
                    result = try await self.inference.infer(text: text, action: action, additionalInstructions: additionalInstructions)
                }
                guard !Task.isCancelled, requestID == id else { return }
                elapsedSeconds = Date().timeIntervalSince(requestStartedAt ?? started)
                requestStartedAt = nil
                self.rawRequest = inference.lastRawRequest
                self.rawResponse = inference.lastRawResponse
                self.resultMeasure = nil
                self.streamingMarkdown = nil
                self.result = result
                if action == .writeEnglish || result.candidates.count == 1 { chooseCandidate(0) }
                phase = .result
                Diagnostics.event("inference_success", action: action.rawValue, mode: "stream")
                Diagnostics.metrics(elapsed: Date().timeIntervalSince(started), characters: text.count)
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                elapsedSeconds = Date().timeIntervalSince(requestStartedAt ?? started)
                requestStartedAt = nil
                self.rawRequest = inference.lastRawRequest
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
