import AssistantCore

extension AssistantSession {
    /// Metadata is split separately so it cannot enter copy or replacement text.
    var liveWriteSections: (cards: [String?], direction: String?, notes: String?, summary: String?, current: Int?) {
        var sections = StreamingSections()
        sections.ingest(streamingMarkdown ?? "", known: StreamingSections.writeHeadings)
        let cards = WritingMarkdownPayload.answerHeadings.map { sections.displayOrNil($0) }
        let direction = sections.displayOrNil("Direction").flatMap { WritingMarkdownPayload.directionLabel($0) }
        let current = sections.current.flatMap { WritingMarkdownPayload.answerHeadings.firstIndex(of: $0) }
        return (cards, direction, sections.displayOrNil("Notes"), sections.displayOrNil("Summary"), current)
    }

    var liveUnderstandSections: (translation: String?, notes: String?) {
        var sections = StreamingSections()
        sections.ingest(streamingMarkdown ?? "", known: StreamingSections.understandHeadings)
        return (sections.displayOrNil("Translation"), sections.displayOrNil("Notes"))
    }
}
