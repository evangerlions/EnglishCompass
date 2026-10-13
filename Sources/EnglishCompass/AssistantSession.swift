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
    let preferences: Preferences
    let accessibility: AccessibilityBridge
    let inference: any InferencePerforming
    private var target: CapturedTarget?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?

    init(preferences: Preferences, accessibility: AccessibilityBridge, inference: any InferencePerforming) {
        self.preferences = preferences; self.accessibility = accessibility; self.inference = inference
    }
    var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("--ui-test") }
    var hasCapturedTarget: Bool { target != nil }
    var canReplace: Bool {
        action == .writeEnglish && phase == .result && candidateIndex != nil && warnings.isEmpty &&
        !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        target.map { accessibility.canWrite($0) } == true
    }
    func begin(_ action: AssistantAction, capture: Bool = true, completion: @escaping (CGRect?) -> Void = { _ in }) {
        cancel(close: false)
        self.action = action
        phase = .input; input = ""; suggestion = ""; result = nil; candidateIndex = nil
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
        elapsedSeconds = nil; requestStartedAt = Date()
        let id = UUID(); requestID = id
        let text = input, action = action, additionalInstructions = preferences.additionalInstructions
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
                } else {
                    result = try await inference.infer(text: text, action: action, additionalInstructions: additionalInstructions)
                }
                guard !Task.isCancelled, requestID == id else { return }
                elapsedSeconds = Date().timeIntervalSince(requestStartedAt ?? started)
                requestStartedAt = nil
                self.rawRequest = inference.lastRawRequest
                self.rawResponse = inference.lastRawResponse
                self.result = result
                if action == .writeEnglish || result.candidates.count == 1 { chooseCandidate(0) }
                phase = .result
                Diagnostics.event("inference_success", action: action.rawValue, mode: "non-thinking")
                Diagnostics.metrics(elapsed: Date().timeIntervalSince(started), characters: text.count)
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                elapsedSeconds = Date().timeIntervalSince(requestStartedAt ?? started)
                requestStartedAt = nil
                self.rawRequest = inference.lastRawRequest
                self.rawResponse = inference.lastRawResponse
                phase = .error
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
