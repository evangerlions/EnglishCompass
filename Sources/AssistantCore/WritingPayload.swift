import Foundation

/// Compatibility is limited to usable final answers, never malformed JSON or tool calls.
enum WritingPayload {
    static func parse(_ content: String) throws -> ModelResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = try? JSONSerialization.jsonObject(with: Data(content.utf8)) {
            guard let object = value as? [String: Any],
                  Set(object.keys).isSubset(of: ["candidates", "explanations", "summary", "highlights"]),
                  let candidates = object["candidates"] as? [String], (1...3).contains(candidates.count) else {
                throw AssistantFailure.invalidResult
            }
            let explanations: [String] = try optional(object, key: "explanations", default: [])
            let summary: String = try optional(object, key: "summary", default: "")
            let highlights = try emphasis(object["highlights"])
            return try ModelResult(candidates: candidates, explanations: explanations,
                                   summary: summary, highlights: highlights).validated()
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
}
