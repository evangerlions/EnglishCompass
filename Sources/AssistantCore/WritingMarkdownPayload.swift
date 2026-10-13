import Foundation

/// Fixed-section Markdown returned by the writing model. Markdown is retained for
/// display while each section also exposes plain text for copy and replacement.
enum WritingMarkdownPayload {
    private static let sections = ["General", "Conversational", "Academic"]

    static func parse(_ content: String) throws -> ModelResult {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalized.contains("<think"), !normalized.contains("</think") else {
            throw AssistantFailure.invalidResult
        }

        var bodies: [String: String] = [:]
        var current: String?
        var lines: [String] = []

        func commit() {
            guard let current else { return }
            bodies[current] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeAll(keepingCapacity: true)
        }

        for line in normalized.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                commit()
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                guard sections.contains(heading) || heading == "Notes", bodies[heading] == nil else {
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

        guard Set(bodies.keys) == Set(sections + ["Notes"]) else { throw AssistantFailure.invalidResult }
        let candidates = try sections.map { heading -> String in
            guard let markdown = bodies[heading], !markdown.isEmpty else { throw AssistantFailure.invalidResult }
            let plain = plainText(markdown)
            guard !plain.isEmpty else { throw AssistantFailure.invalidResult }
            return plain
        }
        let notes = bodies["Notes"] ?? ""
        let explanations = notes.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        guard explanations.count == 3 else { throw AssistantFailure.invalidResult }

        return try ModelResult(candidates: candidates, explanations: explanations,
                               summary: "", highlights: [],
                               markdownCandidates: sections.compactMap { bodies[$0] }).validated()
    }

    static func plainText(_ markdown: String) -> String {
        do {
            let attributed = try AttributedString(markdown: markdown,
                                                  options: .init(interpretedSyntax: .full))
            return String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // A deterministic fallback for malformed inline Markdown. Structural
            // parsing still fails closed; only display markup is stripped here.
            return markdown
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
