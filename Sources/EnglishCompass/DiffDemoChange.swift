import AppKit
import AssistantCore

/// Display grouping only. Does not infer grammar categories or change the diff.
struct DiffDemoChange: Identifiable, Equatable {
    let id: Int
    let before: String
    let after: String
    let proposedRange: NSRange

    static func groups(_ parts: [DiffPart]) -> [DiffDemoChange] {
        var groups: [DiffDemoChange] = []
        var pending: [DiffPart] = []
        func flush() {
            guard let first = pending.first else { return }
            let before = pending.filter { $0.kind == .removed }.map(\.text).joined()
            let after = pending.filter { $0.kind == .inserted }.map(\.text).joined()
            groups.append(DiffDemoChange(id: groups.count, before: before, after: after,
                                         proposedRange: NSRange(location: first.proposedRange.location,
                                                                length: after.utf16.count)))
            pending.removeAll(keepingCapacity: true)
        }
        for part in parts {
            if part.kind == .unchanged { flush() }
            else { pending.append(part) }
        }
        flush()
        return groups
    }
}

enum DiffDemoReview {
    static let changeID = NSAttributedString.Key("EnglishCompassDiffChange")

    static func text(_ parts: [DiffPart], selectedID: Int?) -> NSAttributedString {
        let revised = parts.filter { $0.kind != .removed }.map(\.text).joined()
        let rich = NSMutableAttributedString(string: revised, attributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.textColor
        ])
        for change in DiffDemoChange.groups(parts) where change.proposedRange.length > 0 {
            rich.addAttributes([
                changeID: change.id,
                .backgroundColor: NSColor.systemTeal.withAlphaComponent(change.id == selectedID ? 0.25 : 0.09),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.systemTeal.withAlphaComponent(0.7)
            ], range: change.proposedRange)
        }
        return rich
    }
}
