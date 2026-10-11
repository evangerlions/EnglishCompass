import XCTest
@testable import AssistantCore

final class SafetyTests: XCTestCase {
    func testSelectionReplacementKeepsSurroundingText() throws {
        let snapshot = try DraftSnapshot(fullText: "prefix bad suffix", range: NSRange(location: 7, length: 3))
        XCTAssertEqual(snapshot.input, "bad")
        XCTAssertEqual(try snapshot.replacing(with: "good", current: snapshot.fullText), "prefix good suffix")
    }
    func testChangedDraftIsNeverOverwritten() throws {
        let snapshot = try DraftSnapshot(fullText: "original", range: NSRange(location: 0, length: 8))
        XCTAssertThrowsError(try snapshot.replacing(with: "replacement", current: "edited")) { error in
            XCTAssertEqual(error as? AssistantFailure, .changedDraft)
        }
    }
    func testInvalidRangesAreRejected() {
        XCTAssertThrowsError(try DraftSnapshot(fullText: "hi", range: NSRange(location: NSNotFound, length: 1)))
        XCTAssertThrowsError(try DraftSnapshot(fullText: "hi", range: NSRange(location: 1, length: Int.max)))
    }
    func testUTF16Selection() throws {
        let snapshot = try DraftSnapshot(fullText: "🌍 fix bug", range: NSRange(location: 3, length: 3))
        XCTAssertEqual(snapshot.input, "fix")
        XCTAssertEqual(try snapshot.replacing(with: "resolve", current: snapshot.fullText), "🌍 resolve bug")
    }
    func testCorrectTextCanRemainUnchanged() {
        let text = "Run `flutter test` on /tmp/a using https://example.com for 12 tests."
        XCTAssertTrue(ProtectionRules.check(source: text, candidate: text, terms: []).canReplace)
    }
    func testChangedCodeBlocksReplacement() {
        XCTAssertFalse(ProtectionRules.check(source: "Run `rm -i`", candidate: "Run `rm -rf`", terms: []).canReplace)
    }
    func testDuplicateProtectedTokensCannotDisappear() {
        XCTAssertFalse(ProtectionRules.check(source: "Use 5 and 5", candidate: "Use 5", terms: []).canReplace)
    }
    func testURLAndEmailCannotChange() {
        XCTAssertFalse(ProtectionRules.check(source: "Read https://a.com", candidate: "Read https://b.com", terms: []).canReplace)
        XCTAssertFalse(ProtectionRules.check(source: "Email a@b.com", candidate: "Email x@b.com", terms: []).canReplace)
    }
    func testNegationAndModalityCannotChange() {
        for (source, candidate) in [("You must not send", "You may send"), ("Do not run", "Do run"), ("Never delete", "Delete")] {
            XCTAssertFalse(ProtectionRules.check(source: source, candidate: candidate, terms: []).canReplace)
        }
    }
    func testProtectedTerms() {
        XCTAssertFalse(ProtectionRules.check(source: "Use ZOOK", candidate: "Use Zook", terms: ["ZOOK"]).canReplace)
    }
    func testAddedNegationIsBlocked() {
        XCTAssertFalse(ProtectionRules.check(source: "Please delete this", candidate: "Please do not delete this", terms: []).canReplace)
    }
    func testRelativePathPrefixesAreProtected() {
        XCTAssertFalse(ProtectionRules.check(source: "Use src/config.json", candidate: "Use prod/config.json", terms: []).canReplace)
    }
    func testSignedAndPercentageNumbersArePreserved() {
        for (source, candidate) in [("Use 5%", "Use 5"), ("Use -5", "Use 5"), ("Use +5", "Use -5")] {
            XCTAssertFalse(ProtectionRules.check(source: source, candidate: candidate, terms: []).canReplace)
        }
    }
    func testNormalizationChangesInvalidateUTF16Snapshot() throws {
        let snapshot = try DraftSnapshot(fullText: "\u{00e9}X", range: NSRange(location: 1, length: 1))
        XCTAssertThrowsError(try snapshot.replacing(with: "Y", current: "e\u{0301}X"))
    }
    func testMarkdownAndNewlinesCannotChange() {
        XCTAssertFalse(ProtectionRules.check(source: "# Title\n- item", candidate: "Title\nitem", terms: []).canReplace)
        XCTAssertFalse(ProtectionRules.check(source: "one\ntwo", candidate: "one two", terms: []).canReplace)
    }
    func testResultContractRejectsReasoningAndMalformedCandidates() {
        XCTAssertThrowsError(try ModelResult(candidates: []).validated())
        XCTAssertThrowsError(try ModelResult(candidates: [" "]).validated())
        XCTAssertThrowsError(try ModelResult(candidates: ["<think>secret"]).validated())
        XCTAssertThrowsError(try ModelResult(candidates: ["ok"], explanations: ["a", "b", "c"]).validated())
    }
    func testAmbiguityHasTwoExplicitCandidates() throws {
        XCTAssertEqual(try ModelResult(candidates: ["one", "two"]).validated().candidates.count, 2)
    }
    func testCloudFailuresHaveSpecificRecovery() {
        for code in ["context_limit", "cloud_key_missing", "cloud_keychain_access", "cloud_auth", "cloud_rate_limit", "invalid_result"] {
            XCTAssertNotNil(AssistantFailure(rawValue: code))
        }
    }
    func testDiffShowsBothRemovalAndInsertion() {
        let parts = TextDiff.parts(original: "I has a bug", proposed: "I have a bug")
        XCTAssertTrue(parts.contains { $0.kind == .removed && $0.text == "has" })
        XCTAssertTrue(parts.contains { $0.kind == .inserted && $0.text == "have" })
    }
}
