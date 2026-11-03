import Foundation

public struct DiffPart: Equatable, Sendable {
    public enum Kind: Sendable { case unchanged, inserted, removed }
    public let text: String
    public let kind: Kind
    /// UTF-16 ranges in the untouched input strings. Insertions/removals have
    /// a zero-length range on the side that does not contain their text.
    public let originalRange: NSRange
    public let proposedRange: NSRange
}

public struct TextDiffResult: Equatable, Sendable {
    public let parts: [DiffPart]
    /// Large unmatched regions are shown as a whole replacement, not a guessed
    /// detailed diff. Both source strings still reconstruct exactly.
    public let isCoarse: Bool
}

public enum TextDiff {
    public enum Granularity: String, CaseIterable, Sendable {
        case words, characters
    }

    public static func parts(original: String, proposed: String,
                             granularity: Granularity = .words) -> [DiffPart] {
        compare(original: original, proposed: proposed, granularity: granularity).parts
    }

    /// Exact text diff only: no normalization, Markdown parsing or model call.
    /// Uses grapheme boundaries so emoji and combining characters stay intact.
    public static func compare(original: String, proposed: String,
                               granularity: Granularity = .words) -> TextDiffResult {
        let old = tokens(original, granularity: granularity)
        let new = tokens(proposed, granularity: granularity)
        // Swift String equality is canonically equivalent. Compare UTF-16 keys
        // instead so canonically equivalent but byte-distinct text is not lost.
        let oldKeys = old.map { Array($0.utf16) }
        let newKeys = new.map { Array($0.utf16) }
        var prefix = 0
        while prefix < min(old.count, new.count), oldKeys[prefix] == newKeys[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              oldKeys[old.count - 1 - suffix] == newKeys[new.count - 1 - suffix] { suffix += 1 }
        let oldEnd = old.count - suffix
        let newEnd = new.count - suffix
        let oldMiddle = Array(oldKeys[prefix..<oldEnd])
        let newMiddle = Array(newKeys[prefix..<newEnd])
        // Bound the standard library's worst-case work for unrelated long text.
        let isCoarse = !oldMiddle.isEmpty && !newMiddle.isEmpty
            && oldMiddle.count > 2_000_000 / newMiddle.count
        var removed = Set<Int>()
        var inserted = Set<Int>()
        if isCoarse {
            removed = Set(prefix..<oldEnd)
            inserted = Set(prefix..<newEnd)
        } else {
            let changes = newMiddle.difference(from: oldMiddle)
            for change in changes {
                switch change {
                case let .remove(offset, _, _): removed.insert(prefix + offset)
                case let .insert(offset, _, _): inserted.insert(prefix + offset)
                }
            }
        }

        var result: [DiffPart] = []
        var i = 0, j = 0, oldOffset = 0, newOffset = 0
        var runKind: DiffPart.Kind?
        var fragments: [String] = []
        var runOldStart = 0, runNewStart = 0
        func flushRun() {
            guard let kind = runKind else { return }
            result.append(DiffPart(
                text: fragments.joined(), kind: kind,
                originalRange: NSRange(location: runOldStart, length: oldOffset - runOldStart),
                proposedRange: NSRange(location: runNewStart, length: newOffset - runNewStart)))
            fragments.removeAll(keepingCapacity: true)
        }
        func append(_ text: String, _ kind: DiffPart.Kind, oldLength: Int, newLength: Int) {
            if runKind != kind {
                flushRun()
                runKind = kind
                runOldStart = oldOffset; runNewStart = newOffset
            }
            fragments.append(text)
            oldOffset += oldLength
            newOffset += newLength
        }
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                append(old[i], .removed, oldLength: old[i].utf16.count, newLength: 0)
                i += 1
            } else if j < new.count, inserted.contains(j) {
                append(new[j], .inserted, oldLength: 0, newLength: new[j].utf16.count)
                j += 1
            } else if i < old.count, j < new.count {
                append(old[i], .unchanged, oldLength: old[i].utf16.count, newLength: new[j].utf16.count)
                i += 1; j += 1
            }
        }
        flushRun()
        return TextDiffResult(parts: result, isCoarse: isCoarse)
    }

    private static func tokens(_ text: String, granularity: Granularity) -> [String] {
        if granularity == .characters { return text.map(String.init) }
        var result: [String] = []
        var word = ""
        func flushWord() {
            if !word.isEmpty { result.append(word); word = "" }
        }
        for character in text {
            if isWordCharacter(character) {
                word.append(character)
            } else {
                flushWord()
                // Preserve every separator, including spaces, tabs and CRLF.
                result.append(String(character))
            }
        }
        flushWord()
        return result
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        // CJK without spaces uses grapheme tokens; this is not linguistic word
        // segmentation. Latin/other alphabetic runs and digits use word tokens.
        guard !character.unicodeScalars.contains(where: { scalar in
            (0x3400...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x20000...0x323AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
        }) else { return false }
        return character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }
    }
}
