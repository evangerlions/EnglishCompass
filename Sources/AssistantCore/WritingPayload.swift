import Foundation

/// Compatibility is limited to usable final answers, never malformed JSON or tool calls.
enum WritingPayload {
    static func parse(_ content: String) throws -> ModelResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = try? JSONSerialization.jsonObject(with: Data(content.utf8)) {
            guard let object = value as? [String: Any],
                  Set(object.keys).isSubset(of: ["candidates", "explanations", "summary", "highlights", "markdownCandidates", "revisionDirection"]),
                  (object["markdownCandidates"] == nil || (object["markdownCandidates"] as? [String])?.isEmpty == true),
                  let candidates = object["candidates"] as? [String], (1...3).contains(candidates.count) else {
                throw AssistantFailure.invalidResult
            }
            let explanations: [String] = try optional(object, key: "explanations", default: [])
            let summary: String = try optional(object, key: "summary", default: "")
            let direction: String? = try object["revisionDirection"].map { value in
                guard let text = value as? String, let label = WritingMarkdownPayload.directionLabel(text) else {
                    throw AssistantFailure.invalidResult
                }
                return label
            }
            let rawHighlights = try emphasis(object["highlights"])
            let highlights = sanitize(rawHighlights, for: candidates)
            return try ModelResult(candidates: candidates, explanations: explanations,
                                   summary: summary, highlights: highlights, revisionDirection: direction).validated()
        }
        // Do not turn a truncated/invalid structured response into a copyable answer.
        guard !trimmed.isEmpty, !["{", "[", "\"", "```json", "```\n{"].contains(where: trimmed.lowercased().hasPrefix) else {
            throw AssistantFailure.invalidResult
        }
        return try ModelResult(candidates: [content]).validated()
    }

    private static func optional<T>(_ object: [String: Any], key: String, default fallback: T) throws -> T {
        guard let value = object[key] else { return fallback }
        guard let typed = value as? T else { throw AssistantFailure.invalidResult }
        return typed
    }

    private static func emphasis(_ value: Any?) throws -> [[String]] {
        guard let value else { return [] }
        if let arrays = value as? [[String]] { return arrays }
        if let strings = value as? [String] { return strings.map { $0.isEmpty ? [] : [$0] } }
        throw AssistantFailure.invalidResult
    }

    private static func sanitize(_ highlights: [[String]], for candidates: [String]) -> [[String]] {
        guard highlights.count == candidates.count else { return highlights }
        return highlights.enumerated().map { index, terms in
            Array(terms.filter { term in
                !term.isEmpty && candidates[index].contains(term) &&
                !term.contains("<think") && !term.contains("</think")
            }.prefix(3))
        }
    }
}
