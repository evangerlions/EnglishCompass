import Foundation
import XCTest
@testable import AssistantCore

final class TextDiffTests: XCTestCase {
    func testWordCorrectionKeepsWholeWordChanges() {
        let result = TextDiff.compare(original: "She go home.", proposed: "She goes home.")
        XCTAssertTrue(result.parts.contains { $0.kind == .removed && $0.text == "go" })
        XCTAssertTrue(result.parts.contains { $0.kind == .inserted && $0.text == "goes" })
        assertRoundTrip("She go home.", "She goes home.", result.parts)
    }

    func testCharacterModeShowsSuffixInsertion() {
        let parts = TextDiff.parts(original: "go", proposed: "goes", granularity: .characters)
        XCTAssertEqual(parts.map(\.kind), [.unchanged, .inserted])
        XCTAssertEqual(parts.map(\.text), ["go", "es"])
        assertRoundTrip("go", "goes", parts)
    }

    func testWhitespacePunctuationAndLineEndingsAreLossless() {
        let old = "Hello  world!\r\n\r\nFirst\tline.\n"
        let new = "Hello, world!\nFirst line.\n\n"
        for mode in TextDiff.Granularity.allCases {
            assertRoundTrip(old, new, TextDiff.parts(original: old, proposed: new, granularity: mode))
        }
    }

    func testCJKEmojiAndCombiningCharactersAreNotSplit() {
        let old = "今天要修复。👩🏽‍💻 Cafe\u{301} 🇨🇳"
        let new = "今天需要修复！👨🏻‍💻 Cafe\u{301} 🇬🇧"
        for mode in TextDiff.Granularity.allCases {
            let parts = TextDiff.parts(original: old, proposed: new, granularity: mode)
            assertRoundTrip(old, new, parts)
            let boundaries = Set((old + new).map(String.init))
            XCTAssertTrue(parts.allSatisfy { $0.text.allSatisfy { boundaries.contains(String($0)) } })
        }
    }

    func testCanonicalEquivalenceDoesNotHideCodeUnitChanges() {
        let old = "caf\u{00E9}"
        let new = "cafe\u{0301}"
        for mode in TextDiff.Granularity.allCases {
            let parts = TextDiff.parts(original: old, proposed: new, granularity: mode)
            XCTAssertTrue(parts.contains { $0.kind == .removed })
            XCTAssertTrue(parts.contains { $0.kind == .inserted })
            assertRoundTrip(old, new, parts)
        }
    }

    func testEmptyIdenticalRepeatedAndReorderedTexts() {
        let pairs = [
            ("", ""), ("", "New\ntext"), ("Old\ttext", ""),
            (" same\n\ntext ", " same\n\ntext "),
            ("very very fast", "very fast"), ("a b a b", "b a b a"),
            ("one\ntwo\nthree", "three\none\ntwo"),
            ("**literal** <tag>", "*literal* <other>")
        ]
        for (old, new) in pairs {
            for mode in TextDiff.Granularity.allCases {
                let parts = TextDiff.parts(original: old, proposed: new, granularity: mode)
                assertRoundTrip(old, new, parts)
                for (first, second) in zip(parts, parts.dropFirst()) {
                    XCTAssertNotEqual(first.kind, second.kind, "Adjacent runs must be coalesced")
                }
            }
        }
    }

    func testSmallTokenCombinationsRoundTrip() {
        let corpus = ["", "a", "b", " ", "\n", "中", "👩🏽‍💻", "a a", "a\tb", "b a"]
        for old in corpus {
            for new in corpus {
                for mode in TextDiff.Granularity.allCases {
                    assertRoundTrip(old, new, TextDiff.parts(original: old, proposed: new, granularity: mode))
                }
            }
        }
    }

    func testLargeUnrelatedRegionFallsBackWithoutTruncation() {
        let old = String(repeating: "中", count: 2_000)
        let new = String(repeating: "文", count: 2_000)
        let result = TextDiff.compare(original: old, proposed: new)
        XCTAssertTrue(result.isCoarse)
        XCTAssertEqual(result.parts.map(\.kind), [.removed, .inserted])
        assertRoundTrip(old, new, result.parts)
    }

    func testCommonPrefixAndSuffixAvoidUnnecessaryCoarseDiff() {
        let padding = String(repeating: "a ", count: 2_000)
        let old = padding + "go" + padding
        let new = padding + "goes" + padding
        let result = TextDiff.compare(original: old, proposed: new)
        XCTAssertFalse(result.isCoarse)
        assertRoundTrip(old, new, result.parts)
    }

    private func assertRoundTrip(_ old: String, _ new: String, _ parts: [DiffPart],
                                 file: StaticString = #filePath, line: UInt = #line) {
        let reconstructedOld = parts.filter { $0.kind != .inserted }.map(\.text).joined()
        let reconstructedNew = parts.filter { $0.kind != .removed }.map(\.text).joined()
        XCTAssertEqual(Array(reconstructedOld.utf16), Array(old.utf16), file: file, line: line)
        XCTAssertEqual(Array(reconstructedNew.utf16), Array(new.utf16), file: file, line: line)
        var oldOffset = 0, newOffset = 0
        for part in parts {
            XCTAssertFalse(part.text.isEmpty, file: file, line: line)
            XCTAssertEqual(part.originalRange.location, oldOffset, file: file, line: line)
            XCTAssertEqual(part.proposedRange.location, newOffset, file: file, line: line)
            let text = Array(part.text.utf16)
            if part.kind != .inserted {
                XCTAssertEqual(Array((old as NSString).substring(with: part.originalRange).utf16), text, file: file, line: line)
            } else {
                XCTAssertEqual(part.originalRange.length, 0, file: file, line: line)
            }
            if part.kind != .removed {
                XCTAssertEqual(Array((new as NSString).substring(with: part.proposedRange).utf16), text, file: file, line: line)
            } else {
                XCTAssertEqual(part.proposedRange.length, 0, file: file, line: line)
            }
            oldOffset += part.originalRange.length
            newOffset += part.proposedRange.length
        }
        XCTAssertEqual(oldOffset, old.utf16.count, file: file, line: line)
        XCTAssertEqual(newOffset, new.utf16.count, file: file, line: line)
    }
}
