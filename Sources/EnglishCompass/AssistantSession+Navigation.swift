import Foundation

extension AssistantSession {
    func returnToInput() {
        cancel(close: false)
        inference.cancel()
        questions.reset()
        speech.stop()
        result = nil; suggestion = ""; candidateIndex = nil; streamingMarkdown = nil
        resultMeasure = nil; inputMeasure = nil; showsResultScrollIndicators = false
        warnings = []; message = ""; rawRequest = nil; rawResponse = nil
    }

    func openQuestions() {
        guard phase == .result, !isStreaming, let result else { return }
        let answers = result.candidates.enumerated().map { "Answer \($0.offset + 1):\n\($0.element)" }
        let context = (["Task: \(action.title)", "Original text:\n\(input)"] + answers +
                       result.explanations + [result.summary]).joined(separator: "\n\n")
        questions.configure(context: context, model: requestModel)
        isQuestionOpen = true
    }

    func closeQuestions() {
        questions.stop()
        isQuestionOpen = false
    }
}
