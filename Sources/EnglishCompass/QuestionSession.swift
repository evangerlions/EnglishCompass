import SwiftUI
import AssistantCore

/// One in-memory conversation per transformation; shares the existing transport
/// and credential cache, but never the transformation's response parser.
@MainActor
final class QuestionSession: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [QuestionMessage] = []
    @Published private(set) var isSending = false
    @Published private(set) var error = ""
    private(set) var context = ""
    private(set) var model: QwenModel = .flash37
    private let inference: any InferencePerforming
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(inference: any InferencePerforming) { self.inference = inference }

    func configure(context: String, model: QwenModel) {
        if self.context != context || self.model != model { reset() }
        self.context = context
        self.model = model
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending, !text.isEmpty else { return }
        let user = QuestionMessage(role: .user, content: text)
        let history = messages + [user]
        do { try QuestionAPIContract.validate(context: context, messages: history) }
        catch { self.error = error.localizedDescription; return }
        let reply = QuestionMessage(role: .assistant, content: "")
        messages = history + [reply]
        draft = ""; error = ""; isSending = true
        let id = UUID(); generation = id
        let context = context, model = model
        task = Task { [weak self] in
            guard let self, !Task.isCancelled, self.generation == id else { return }
            self.inference.useModel(model)
            do {
                let answer = try await self.inference.answerQuestion(context: context, messages: history) { [weak self] delta in
                    guard let self, self.generation == id, !Task.isCancelled,
                          let index = self.messages.firstIndex(where: { $0.id == reply.id }) else { return }
                    self.messages[index].content += delta
                }
                guard self.generation == id, !Task.isCancelled else { return }
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AssistantFailure.invalidResult
                }
                if let index = self.messages.firstIndex(where: { $0.id == reply.id }) {
                    self.messages[index].content = answer
                }
            } catch {
                guard self.generation == id, !Task.isCancelled else { return }
                self.error = (error as? AssistantFailure)?.localizedDescription ?? "Unable to answer. Please try again."
                if self.messages.last?.content.isEmpty == true {
                    self.messages.removeLast()
                    self.messages.removeAll { $0.id == user.id }
                    self.draft = text
                }
            }
            guard self.generation == id else { return }
            self.isSending = false; self.task = nil
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        if isSending {
            inference.cancel()
            if messages.last?.content.isEmpty == true { messages.removeLast() }
        }
        isSending = false
    }

    func clearConversation() {
        stop()
        messages = []; draft = ""; error = ""
    }

    func reset() {
        clearConversation()
        context = ""
    }
}
