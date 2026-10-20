import SwiftUI
import AppKit

/// Collapsible, syntax-highlighted view of a raw provider response body.
/// Shown only after a 200 response that failed content parsing, so the user can
/// inspect what the model actually returned.
struct JSONDebugView: View {
    let raw: String
    @State private var expanded = false
    private let accent = Color(red: 0.08, green: 0.43, blue: 0.40)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(expanded ? "Hide raw response" : "Show raw response")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("raw_response_toggle")

            if expanded {
                ScrollView {
                    Text(highlighted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 220)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.10))
                )
                .accessibilityIdentifier("raw_response_body")
            }
        }
    }

    private var highlighted: AttributedString {
        Self.highlight(raw)
    }

    // MARK: - Syntax highlighter

    static func highlight(_ raw: String) -> AttributedString {
        let pretty = Self.pretty(raw)
        let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString(
            string: pretty,
            attributes: [.font: baseFont,
                         .foregroundColor: NSColor.labelColor]
        )

        var i = pretty.startIndex
        var inString = false
        var stringStart: String.Index?

        func colorRange(_ start: String.Index, _ end: String.Index, _ color: NSColor) {
            let ns = NSRange(start...end, in: pretty)
            result.addAttribute(.foregroundColor, value: color, range: ns)
        }

        while i < pretty.endIndex {
            let c = pretty[i]
            if inString {
                if c == "\\" {
                    // Skip the escaped character.
                    let next = pretty.index(after: i)
                    if next < pretty.endIndex { i = next }
                } else if c == "\"" {
                    inString = false
                    if let s = stringStart {
                        // Look ahead past whitespace to decide key vs. value.
                        var j = pretty.index(after: i)
                        while j < pretty.endIndex,
                              pretty[j] == " " || pretty[j] == "\t" || pretty[j] == "\n" {
                            j = pretty.index(after: j)
                        }
                        let isKey = j < pretty.endIndex && pretty[j] == ":"
                        colorRange(s, i, isKey ? .systemBlue : .systemGreen)
                    }
                }
            } else {
                if c == "\"" {
                    inString = true
                    stringStart = i
                } else if c == "-" || c.isNumber {
                    // Consume a number literal.
                    let start = i
                    while i < pretty.endIndex {
                        let ch = pretty[i]
                        if ch == "-" || ch == "+" || ch == "." || ch.isNumber || ch == "e" || ch == "E" {
                            i = pretty.index(after: i)
                        } else { break }
                    }
                    colorRange(start, pretty.index(before: i), .systemOrange)
                    continue
                } else if c == "t", pretty[i...].hasPrefix("true") {
                    let end = pretty.index(i, offsetBy: 4, limitedBy: pretty.endIndex) ?? pretty.endIndex
                    colorRange(i, pretty.index(before: end), .systemRed)
                    i = end; continue
                } else if c == "f", pretty[i...].hasPrefix("false") {
                    let end = pretty.index(i, offsetBy: 5, limitedBy: pretty.endIndex) ?? pretty.endIndex
                    colorRange(i, pretty.index(before: end), .systemRed)
                    i = end; continue
                } else if c == "n", pretty[i...].hasPrefix("null") {
                    let end = pretty.index(i, offsetBy: 4, limitedBy: pretty.endIndex) ?? pretty.endIndex
                    colorRange(i, pretty.index(before: end), .systemRed)
                    i = end; continue
                }
            }
            i = pretty.index(after: i)
        }

        // Text consumes SwiftUI attributes; AppKit-only colors can render as plain text.
        var highlighted = AttributedString(pretty)
        highlighted.font = .system(size: 11, design: .monospaced)
        result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let color = value as? NSColor,
                  let stringRange = Range(range, in: pretty),
                  let start = AttributedString.Index(stringRange.lowerBound, within: highlighted),
                  let end = AttributedString.Index(stringRange.upperBound, within: highlighted) else { return }
            highlighted[start..<end].foregroundColor = Color(nsColor: color)
        }
        return highlighted
    }

    /// Try to pretty-print JSON; fall back to the raw string if it isn't valid JSON.
    private static func pretty(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: pretty, encoding: .utf8)
        else { return raw }
        return text
    }
}
