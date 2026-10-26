import Foundation
import AssistantCore

/// Builds a usable result from a malformed/partial model response so the panel
/// never dismisses back to the input page after a long wait. It uses whatever
/// fixed sections it can recognize, then falls back to the whole content.
///
/// This is display/copy only — it is never used for the strict "Replace" path
/// and is shown with a visible warning.
enum BestEffortResult {
    static func make(content: String, action: AssistantAction) -> ModelResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ModelResult(candidates: [""])
        }

        if action == .writeEnglish {
            var sections = StreamingSections()
            sections.ingest(trimmed, known: StreamingSections.writeHeadings)
            let md = WritingMarkdownPayload.answerHeadings.compactMap { sections.displayOrNil($0) }
            // Keep recognized answer bodies separate from metadata even when truncated.
            if !md.isEmpty {
                let candidates = md.map { WritingMarkdownPayload.plainText($0) }
                let body = ["Notes", "Summary"].compactMap { heading in
                    sections.displayOrNil(heading).map { "## \(heading)\n\($0)" }
                }.joined(separator: "\n\n")
                if candidates.allSatisfy({ !$0.isEmpty }) {
                    return ModelResult(candidates: candidates, explanations: [], summary: body,
                                       highlights: [], markdownCandidates: md,
                                       revisionDirection: md.count == 2 ? sections.displayOrNil("Direction").flatMap { WritingMarkdownPayload.directionLabel($0) } : nil)
                }
            }
            if sections.order.contains(WritingMarkdownPayload.directionHeading) {
                return ModelResult(candidates: [], summary: trimmed)
            }
            // Otherwise show the whole text as one answer so nothing is lost.
            let plain = WritingMarkdownPayload.plainText(trimmed)
            return ModelResult(candidates: [plain.isEmpty ? trimmed : plain],
                               explanations: [], summary: "", highlights: [],
                               markdownCandidates: [trimmed])
        }

        // Understand: prefer an extracted translation, else the whole text.
        var sections = StreamingSections()
        sections.ingest(trimmed, known: StreamingSections.understandHeadings)
        if let translation = sections.displayOrNil("Translation"),
           let plain = Optional(WritingMarkdownPayload.plainText(translation)), !plain.isEmpty {
            let notes = sections.displayOrNil("Notes") ?? ""
            return ModelResult(candidates: [plain], explanations: [], summary: notes,
                               highlights: [], markdownCandidates: [translation])
        }
        return ModelResult(candidates: [trimmed], explanations: [], summary: "",
                           highlights: [], markdownCandidates: [trimmed])
    }
}
