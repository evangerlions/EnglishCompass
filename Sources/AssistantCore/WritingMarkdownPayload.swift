import Foundation

/// Tolerant parser for the writing response.
///
/// Two answers and a separate card-title direction are structurally required.
/// Only the answer bodies are copied or used for replacement. Everything else (## Notes, ## Summary
/// or any trailing prose) is treated as one Markdown body and shown as-is; it
/// is never used for copy, so its exact shape does not matter. This keeps a
/// response valid even when the provider reorders, merges or truncates the
/// explanatory sections.
public enum WritingMarkdownPayload {
    public static let answerHeadings = ["General", "Alternative"]
    public static let directionHeading = "Direction"

    static func parse(_ content: String) throws -> ModelResult {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalized.contains("<think"), !normalized.contains("</think>") else {
            throw AssistantFailure.invalidResult
        }

        // Split into sections by our fixed headings only.
        var answerBodies: [String: String] = [:]
        var bodySections: [(heading: String, text: String)] = []
        var direction: String?
        var current: String?
        var lines: [String] = []

        func commit() {
            guard let heading = current else { return }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if answerHeadings.contains(heading) {
                answerBodies[heading] = body
            } else if heading == directionHeading {
                direction = body
            } else if !body.isEmpty {
                bodySections.append((heading, body))
            }
            lines.removeAll(keepingCapacity: true)
        }

        for line in normalized.components(separatedBy: "\n") {
            if let heading = answerHeading(line) {
                commit()
                guard answerBodies[heading] == nil else { throw AssistantFailure.invalidResult }
                current = heading
            } else if let heading = otherHeading(line) {
                commit()
                if heading == directionHeading, direction != nil { throw AssistantFailure.invalidResult }
                current = heading
            } else if current != nil {
                lines.append(line)
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Content before the first heading is not part of any card/body.
                throw AssistantFailure.invalidResult
            }
        }
        commit()

        guard let direction, let label = directionLabel(direction) else { throw AssistantFailure.invalidResult }

        // Metadata is never part of the copy-bound answers.
        let markdown = try answerHeadings.map { heading -> String in
            guard let body = answerBodies[heading] else { throw AssistantFailure.invalidResult }
            let plain = plainText(body)
            guard !plain.isEmpty else { throw AssistantFailure.invalidResult }
            return body
        }
        let candidates = markdown.map { plainText($0) }

        // Everything explanatory becomes one Markdown body, headings preserved.
        let body = bodySections
            .map { "## \($0.heading)\n\($0.text)" }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return try ModelResult(candidates: candidates, explanations: [],
                               summary: body, highlights: [],
                               markdownCandidates: markdown, revisionDirection: label).validated()
    }

    /// True when the content uses one of our fixed level-2 headings, even if
    /// malformed. Such content must never fall back to being one plain answer.
    static func looksSectioned(_ content: String) -> Bool {
        content.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n").contains { answerHeading($0) != nil || otherHeading($0) != nil }
    }

    static func answerHeading(_ line: String) -> String? {
        heading(line, candidates: answerHeadings)
    }

    /// Section boundaries are ONLY our fixed names. Any other heading (for
    /// example a `### Background` the user wrote and the model translated) is
    /// ordinary content of the current section, never a new section.
    private static func otherHeading(_ line: String) -> String? {
        heading(line, candidates: [directionHeading] + bodyHeadings)
    }

    static let bodyHeadings = ["Notes", "Summary"]

    static func heading(_ line: String, candidates: [String]) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        let title = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
        return candidates.first { $0.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// A short, free-form Chinese label chosen by the model, never an answer.
    public static func directionLabel(_ source: String) -> String? {
        let label = plainText(source)
        guard !label.isEmpty, label.count <= 40,
              !label.contains("\n"), !label.contains("\r"),
              !label.contains("<think"), !label.contains("</think>") else { return nil }
        return label
    }

    /// Strips inline markup (`**`, `` ` ``, links) for copy and replacement while
    /// keeping line breaks, blank lines and list markers exactly as written.
    public static func plainText(_ markdown: String) -> String {
        do {
            let attributed = try AttributedString(markdown: markdown,
                                                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return markdown
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
