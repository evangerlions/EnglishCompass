import Foundation

public struct DiffPart: Equatable, Sendable {
    public enum Kind: Sendable { case unchanged, inserted, removed }
    public let text: String
    public let kind: Kind
}

public enum TextDiff {
    public static func parts(original: String, proposed: String) -> [DiffPart] {
        let old = original.components(separatedBy: " ")
        let new = proposed.components(separatedBy: " ")
        let changes = new.difference(from: old)
        let removed = Set(changes.compactMap { if case let .remove(offset, _, _) = $0 { return offset }; return nil })
        let inserted = Set(changes.compactMap { if case let .insert(offset, _, _) = $0 { return offset }; return nil })
        var result: [DiffPart] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                result.append(DiffPart(text: old[i], kind: .removed)); i += 1
            } else if j < new.count, inserted.contains(j) {
                result.append(DiffPart(text: new[j], kind: .inserted)); j += 1
            } else if i < old.count, j < new.count {
                result.append(DiffPart(text: new[j], kind: .unchanged)); i += 1; j += 1
            } else { break }
        }
        return result
    }
}
