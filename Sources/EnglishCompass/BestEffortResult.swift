import Foundation
import AssistantCore

/// Builds a usable result from a malformed/partial model response so the panel
/// never dismisses back to the input page after a long wait. It uses whatever
/// fixed sections it can recognize, then falls back to the whole content.
///
/// This is display/copy only — it is never used for the strict "Replace" path
/// and is shown with a visible warning.
enum BestEffortResult {
    static func make(content: String, action: AssistantAction, plainWriteBodies: Bool = false) -> ModelResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ModelResult(candidates: [""])
        }

        if action == .writeEnglish {
            var sections = StreamingSections()
            sections.ingest(trimmed, known: StreamingSections.writeHeadings)
            let originalScore = sections.writeOriginalScore
                ?? (sections.current == WritingMarkdownPayload.scoreHeading
                    ? sections.displayOrNil(WritingMarkdownPayload.scoreHeading).flatMap(WritingMarkdownPayload.score) : nil)
            let grouped = WritingMarkdownPayload.usesGroupedFormat(trimmed)
                || (plainWriteBodies && sections.displayOrNil("Notes") == nil && sections.displayOrNil("Summary") == nil)
            let visible = WritingMarkdownPayload.answerHeadings.indices.filter {
                sections.displayOrNil(WritingMarkdownPayload.answerHeadings[$0]) != nil
            }
            let md = visible.compactMap { sections.displayOrNil(WritingMarkdownPayload.answerHeadings[$0]) }
            if grouped, !md.isEmpty {
                return ModelResult(candidates: md,
                    explanations: visible.map { sections.displayOrNil(WritingMarkdownPayload.explanationHeadings[$0]) ?? "" },
                    revisionDirection: md.count == 2 ? sections.displayOrNil("Direction").flatMap { WritingMarkdownPayload.directionLabel($0) } : nil,
                    usesPlainTextAnswers: true, originalScore: originalScore)
            }
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
            if sections.order.contains(WritingMarkdownPayload.directionHeading)
                || sections.order.contains(WritingMarkdownPayload.scoreHeading) {
                // Metadata-only failures are readable in the note block, not copyable answers.
                return ModelResult(candidates: [], summary: trimmed, originalScore: originalScore)
            }
            // Otherwise show the whole text as one answer so nothing is lost.
            if plainWriteBodies {
                return ModelResult(candidates: [trimmed], explanations: [""], usesPlainTextAnswers: true)
            }
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
