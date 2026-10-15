import Foundation

public struct ProtectionReport: Equatable, Sendable {
    public let warnings: [String]
    public var canReplace: Bool { warnings.isEmpty }
}

public enum ProtectionRules {
    public static func check(source: String, candidate: String, terms: [String]) -> ProtectionReport {
        var warnings: [String] = []
        // Compare multiplicities, not sets: duplicate code, numbers and links matter.
        let patterns = [
            #"(?s)```.*?```|`[^`\n]+`"#,
            #"https?://[^\s<>`]+|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#,
            #"(?<!\w)(?:~?/|\./|\.\./)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+|(?<!\w)(?:~?/|\./|\.\./)[A-Za-z0-9_.-]+|[A-Za-z]:\\[^\s`]+"#,
            #"(?<!\w)[+-]?\d+(?:[./:-]\d+)*(?:%|％)?(?!\w)"#,
            #"\b[A-Za-z]+(?:_[A-Za-z0-9]+)+\b|\b[a-z]+[A-Z][A-Za-z0-9]*\b"#
        ]
        for pattern in patterns where tokens(source, pattern) != tokens(candidate, pattern) {
            warnings.append("Protected code, identifiers, paths, links, or numbers changed.")
            break
        }
        for term in terms where !term.isEmpty && count(term, in: source) != count(term, in: candidate) {
            warnings.append("A protected term changed.")
            break
        }
        let modal = #"(?i)\b(?:not|never|must|may|should|cannot|can't|don't|doesn't|won't|mustn't|shouldn't)\b"#
        let containsChinese = source.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        if tokens(source.lowercased(), modal) != tokens(candidate.lowercased(), modal),
           !containsChinese || !tokens(source.lowercased(), modal).isEmpty {
            warnings.append("Negation or modal wording changed. Check the meaning before copying.")
        }
        return ProtectionReport(warnings: warnings)
    }

    private static func tokens(_ text: String, _ pattern: String) -> [String: Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let string = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: string.length))
            .reduce(into: [:]) { result, match in result[string.substring(with: match.range), default: 0] += 1 }
    }
    private static func count(_ term: String, in text: String) -> Int {
        text.components(separatedBy: term).count - 1
    }
}
