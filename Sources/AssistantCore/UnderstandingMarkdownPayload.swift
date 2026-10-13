import Foundation

/// Fixed-section Markdown for understanding selected English. The translation is
/// separated from explanatory notes so copy stays clean while the UI can render
/// concise terminology and context guidance.
enum UnderstandingMarkdownPayload {
    static func parse(_ content: String) throws -> ModelResult {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalized.contains("<think"), !normalized.contains("</think") else {
            throw AssistantFailure.invalidResult
        }

        let sections = try parseSections(normalized)
        guard Set(sections.keys) == Set(["Translation", "Notes"]),
              let translationMarkdown = sections["Translation"], !translationMarkdown.isEmpty,
              let notesMarkdown = sections["Notes"], !notesMarkdown.isEmpty else {
            throw AssistantFailure.invalidResult
        }
        let translation = WritingMarkdownPayload.plainText(translationMarkdown)
        guard !translation.isEmpty else { throw AssistantFailure.invalidResult }
        return try ModelResult(candidates: [translation], explanations: [], summary: notesMarkdown,
                               highlights: [], markdownCandidates: [translationMarkdown]).validated()
    }

    private static func parseSections(_ content: String) throws -> [String: String] {
        var sections: [String: String] = [:]
        var current: String?
        var lines: [String] = []
        func commit() {
            guard let current else { return }
            sections[current] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeAll(keepingCapacity: true)
        }
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                commit()
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                guard ["Translation", "Notes"].contains(heading), sections[heading] == nil else {
                    throw AssistantFailure.invalidResult
                }
                current = heading
            } else if current != nil {
                lines.append(line)
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AssistantFailure.invalidResult
            }
        }
        commit()
        return sections
    }
}
