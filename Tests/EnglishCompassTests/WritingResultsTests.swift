import AppKit
import XCTest
import AssistantCore
@testable import EnglishCompass

final class WritingResultsTests: XCTestCase {
    @MainActor func testSelectionBoundsAndCopyUseExactAnswerWithoutExplanationOrMarkup() {
        let suite = "WritingResultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AssistantSession(preferences: Preferences(defaults: defaults),
                                       accessibility: AccessibilityBridge(), inference: InferenceService())
        session.result = WritingFixture.result
        session.phase = .result
        session.chooseCandidate(0)
        session.moveCandidate(-1)
        XCTAssertEqual(session.candidateIndex, 0)
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 1)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        session.copy(to: board)
        XCTAssertEqual(board.string(forType: .string), WritingFixture.result.candidates[1])
        XCTAssertEqual(session.message, "Copied.")
        session.moveCandidate(1)
        XCTAssertEqual(session.message, "")
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 2)
        session.copy(to: board)
        XCTAssertEqual(board.string(forType: .string), WritingFixture.result.candidates[2])
        session.phase = .input
        session.moveCandidate(-1)
        XCTAssertEqual(session.candidateIndex, 2)
    }
}
