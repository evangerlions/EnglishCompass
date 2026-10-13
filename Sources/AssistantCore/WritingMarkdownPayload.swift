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
            if let heading = sectionHeading(line) {
                commit()
                guard bodies[heading] == nil else { throw AssistantFailure.invalidResult }
                current = heading
            } else if current != nil {
                lines.append(line)
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AssistantFailure.invalidResult
            }
        }
        commit()

        // Summary is requested by the prompt but optional here, so a response
        // without it still shows the three answers instead of failing.
        let keys = Set(bodies.keys)
        let required = Set(sections + ["Notes"])
        guard keys == required || keys == required.union(["Summary"]) else { throw AssistantFailure.invalidResult }
        let candidates = try sections.map { heading -> String in
            guard let markdown = bodies[heading], !markdown.isEmpty else { throw AssistantFailure.invalidResult }
            let plain = plainText(markdown)
            guard !plain.isEmpty else { throw AssistantFailure.invalidResult }
            return plain
        }
        let notes = bodies["Notes"] ?? ""
        let explanations = notes.components(separatedBy: "\n").compactMap(bulletText).map(removingVersionLabel)
        guard explanations.count == 3 else { throw AssistantFailure.invalidResult }

        return try ModelResult(candidates: candidates, explanations: explanations,
                               summary: bodies["Summary"] ?? "", highlights: [],
                               markdownCandidates: sections.compactMap { bodies[$0] }).validated()
    }

    /// Drops a redundant leading version label such as `**General**:` or
    /// `Conversational：`; each card already shows its own label.
    static func removingVersionLabel(_ note: String) -> String {
        let labels = sections + ["通用", "口语", "学术"]
        var text = Substring(note)
        for label in labels {
            for prefix in ["**\(label)**", label] where text.lowercased().hasPrefix(prefix.lowercased()) {
                let rest = text.dropFirst(prefix.count).drop(while: { $0 == " " })
                if let first = rest.first, ":：-—".contains(first) {
                    let value = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
                text = Substring(note)
            }
        }
        return note
    }

    /// True when the content uses the fixed section headings, even if malformed.
    /// Such content must never fall back to being shown as one plain-text answer.
    static func looksSectioned(_ content: String) -> Bool {
        content.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n").contains { sectionHeading($0) != nil }
    }

    /// Accepts `## General`, `### General`, and case variants of the four headings.
    static func sectionHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return (sections + ["Notes", "Summary"]).first { $0.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// Accepts `-`, `*`, `+`, `•` and `1.` / `1)` list markers.
    static func bulletText(_ line: String) -> String? {
        var text = Substring(line.trimmingCharacters(in: .whitespaces))
        if let first = text.first, "-*+•".contains(first) {
            text = text.dropFirst()
        } else if let dot = text.firstIndex(where: { $0 == "." || $0 == ")" }),
                  !text[..<dot].isEmpty, text[..<dot].allSatisfy(\.isNumber) {
            text = text[text.index(after: dot)...]
        } else {
            return nil
        }
        let value = text.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
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
