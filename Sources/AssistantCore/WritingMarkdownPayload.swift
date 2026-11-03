import Foundation

/// Fixed section boundaries only; explanations never enter copyable answers.
public enum WritingMarkdownPayload {
    public static let answerHeadings = ["General", "Alternative"]
    public static let explanationHeadings = ["General Notes", "Alternative Notes"]
    public static let directionHeading = "Direction"
    public static let groupedHeadings = ["General", "General Notes", "Direction", "Alternative", "Alternative Notes"]
    public static let scoreHeading = "Score"
    public static let scoredHeadings = [scoreHeading] + groupedHeadings
    public static let legacyHeadings = ["General", "Direction", "Alternative", "Notes", "Summary"]

    public static func usesGroupedFormat(_ content: String) -> Bool {
        content.components(separatedBy: "\n").contains {
            heading($0, candidates: explanationHeadings + [scoreHeading]) != nil
        }
    }

    /// Only complete ASCII integer scores are accepted; never round or clamp.
    public static func score(_ source: String) -> Int? {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text == "10" || (text.count == 1 && text.utf8.allSatisfy({ (48...57).contains($0) })) else { return nil }
        return Int(text)
    }

    static func parse(_ content: String) throws -> ModelResult {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalized.contains("<think"), !normalized.contains("</think>") else {
            throw AssistantFailure.invalidResult
        }
        let grouped = usesGroupedFormat(normalized)
        let known = scoredHeadings + bodyHeadings
        var bodies: [String: String] = [:]
        var current: String?
        var lines: [String] = []
        func commit() {
            guard let current else { return }
            bodies[current] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeAll(keepingCapacity: true)
        }
        for line in normalized.components(separatedBy: "\n") {
            if let next = heading(line, candidates: known) {
                commit()
                guard bodies[next] == nil else { throw AssistantFailure.invalidResult }
                current = next
            } else if current != nil {
                lines.append(line)
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AssistantFailure.invalidResult
            }
        }
        commit()
        let originalScore: Int?
        if let rawScore = bodies[scoreHeading] {
            guard let value = score(rawScore) else { throw AssistantFailure.invalidResult }
            originalScore = value
        } else { originalScore = nil }
        guard let general = bodies[answerHeadings[0]], !general.isEmpty else {
            throw AssistantFailure.invalidResult
        }
        var answers = [general]
        var label: String?
        if let alternative = bodies[answerHeadings[1]] {
            guard !alternative.isEmpty,
                  let direction = bodies[directionHeading], let validLabel = directionLabel(direction) else {
                throw AssistantFailure.invalidResult
            }
            answers.append(alternative)
            label = validLabel
        } else {
            // Only the grouped protocol permits omission of the entire second group.
            guard grouped, bodies[directionHeading] == nil, bodies[explanationHeadings[1]] == nil else {
                throw AssistantFailure.invalidResult
            }
        }
        let legacyBody = bodyHeadings.compactMap { name in
            bodies[name].flatMap { $0.isEmpty ? nil : "## \(name)\n\($0)" }
        }.joined(separator: "\n\n")
        if grouped {
            // Keep an explanation slot for every answer that was actually returned.
            // A score never overrides the model's answer or optional-group decision.
            return try ModelResult(candidates: answers,
                explanations: answers.indices.map { bodies[explanationHeadings[$0]] ?? "" },
                summary: legacyBody,
                revisionDirection: label, usesPlainTextAnswers: true, originalScore: originalScore).validated()
        }
        let candidates = answers.map(plainText)
        return try ModelResult(candidates: candidates, summary: legacyBody,
                               markdownCandidates: answers, revisionDirection: label).validated()
    }

    static func looksSectioned(_ content: String) -> Bool {
        content.components(separatedBy: "\n").contains {
            heading($0, candidates: scoredHeadings + bodyHeadings) != nil
        }
    }

    static func answerHeading(_ line: String) -> String? { heading(line, candidates: answerHeadings) }
    static let bodyHeadings = ["Notes", "Summary"]

    static func heading(_ line: String, candidates: [String]) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        let title = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
        return candidates.first { $0.caseInsensitiveCompare(title) == .orderedSame }
    }

    public static func directionLabel(_ source: String) -> String? {
        let label = plainText(source)
        guard !label.isEmpty, label.count <= 40,
              !label.contains("\n"), !label.contains("\r"),
              !label.contains("<think"), !label.contains("</think>") else { return nil }
        return label
    }

    /// Legacy Markdown conversion; new grouped answer bodies remain literal.
    public static func plainText(_ markdown: String) -> String {
        do {
            let attributed = try AttributedString(markdown: markdown,
                                                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return markdown.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
