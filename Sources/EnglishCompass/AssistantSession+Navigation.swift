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
        let answers = result.candidates.enumerated().map { index, text in
            let direction = index == 1 ? result.revisionDirection.map { " (\($0))" } ?? "" : ""
            return "Answer \(index + 1)\(direction):\n\(text)"
        }
        let context = (["Task: \(actionTitle)", "Original text:\n\(input)"] + answers +
                       result.explanations + [result.summary]).joined(separator: "\n\n")
        questions.configure(context: context, model: requestModel)
        isQuestionOpen = true
    }

    func closeQuestions() {
        questions.stop()
        isQuestionOpen = false
    }
}
