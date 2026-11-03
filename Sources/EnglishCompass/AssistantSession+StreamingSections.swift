import Foundation
import AssistantCore

struct LiveWritingSections {
    let cards: [String?]
    let explanations: [String?]
    let finished: [Bool]
    let direction: String?
    let notes: String?
    let summary: String?
    let current: Int?
    let usesPlainTextAnswers: Bool
    let originalScore: Int?

    func plainAnswer(at index: Int) -> String? {
        guard cards.indices.contains(index), let body = cards[index] else { return nil }
        return usesPlainTextAnswers ? body : WritingMarkdownPayload.plainText(body)
    }
}

extension AssistantSession {
    var liveWriteSections: LiveWritingSections {
        let full = streamingMarkdown ?? ""
        var sections = StreamingSections()
        sections.ingest(full, known: StreamingSections.writeHeadings)
        let cards = WritingMarkdownPayload.answerHeadings.map { sections.displayOrNil($0) }
        let direction = sections.displayOrNil("Direction").flatMap { WritingMarkdownPayload.directionLabel($0) }
        let current = sections.current.flatMap { WritingMarkdownPayload.answerHeadings.firstIndex(of: $0) }
        let finished = WritingMarkdownPayload.answerHeadings.map { name -> Bool in
            guard let position = sections.order.firstIndex(of: name) else { return false }
            return sections.order.count > position + 1
        }
        return LiveWritingSections(cards: cards,
            explanations: WritingMarkdownPayload.explanationHeadings.map { sections.displayOrNil($0) },
            finished: finished, direction: direction,
            notes: sections.displayOrNil("Notes"), summary: sections.displayOrNil("Summary"),
            current: current, usesPlainTextAnswers: usesGroupedWriteProtocol || WritingMarkdownPayload.usesGroupedFormat(full),
            originalScore: sections.writeOriginalScore)
    }

    var liveUnderstandSections: (translation: String?, notes: String?) {
        var sections = StreamingSections()
        sections.ingest(streamingMarkdown ?? "", known: StreamingSections.understandHeadings)
        return (sections.displayOrNil("Translation"), sections.displayOrNil("Notes"))
    }
}
