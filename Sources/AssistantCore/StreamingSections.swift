import Foundation

/// Tolerant, incremental splitter for the fixed `## Heading` Markdown protocol.
///
/// Unlike the strict payload parsers (which validate a finished response), this
/// is used ONLY to render streaming partial text: it never throws and never
/// decides success. The full buffer is still strictly parsed via
/// WritingMarkdownPayload / UnderstandingMarkdownPayload when the stream ends.
public struct StreamingSections {
    /// Heading name -> raw Markdown body accumulated so far (not trimmed at the
    /// trailing edge because the next delta may continue the current line).
    public var bodies: [String: String] = [:]
    /// Headings in the order they appeared.
    public var order: [String] = []
    /// Name of the section currently being written, if any.
    public var current: String?

    /// Index of the current heading inside `known`, or nil for a trailing one.
    public func currentHeadingIndex(in known: [String]) -> Int? {
        guard let current else { return nil }
        return known.firstIndex { $0.caseInsensitiveCompare(current) == .orderedSame }
    }

    public init() {}

    public mutating func ingest(_ full: String, known: [String]) {
        var new = StreamingSections()
        for raw in full.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let heading = Self.heading(raw, known: known) {
                if !new.order.contains(heading) { new.order.append(heading) }
                new.current = heading
            } else if let cur = new.current {
                if new.bodies[cur] == nil { new.bodies[cur] = raw }
                else { new.bodies[cur]! += "\n" + raw }
            }
            // Lines before the first heading are ignored while streaming.
        }
        self = new
    }

    /// Returns the body for a heading, leading/trailing whitespace trimmed only
    /// for display; partial trailing lines are preserved (no aggressive trim).
    public func display(_ heading: String) -> String {
        (bodies[heading] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like display but nil when the heading has not appeared / has no body yet.
    public func displayOrNil(_ heading: String) -> String? {
        guard let body = bodies[heading] else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func heading(_ line: String, known: [String]) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return known.first { $0.caseInsensitiveCompare(title) == .orderedSame }
    }
}

public extension StreamingSections {
    static let writeHeadings = ["General", "Direction", "Alternative", "Notes", "Summary"]
    static let understandHeadings = ["Translation", "Notes"]
}
