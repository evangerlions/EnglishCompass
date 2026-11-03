import AppKit
import SwiftUI
import XCTest
import AssistantCore
@testable import EnglishCompass

@MainActor private final class PausedStreamingInference: InferencePerforming {
    var usesStreaming: Bool { true }
    var resume: CheckedContinuation<String, Never>?
    let content = "## General\nFirst answer.\n## Direction\n更自然\n## Alternative\nSecond answer.\n## Notes\n- A note."
    func infer(text: String, action: AssistantAction, additionalInstructions: String) async throws -> ModelResult {
        throw AssistantFailure.cloudUnavailable
    }
    func inferStream(text: String, action: AssistantAction, additionalInstructions: String,
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        onDelta(content)
        return await withCheckedContinuation { resume = $0 }
    }
    func cancel() {}
}

final class ResultInteractionTests: XCTestCase {
    private var suites: [String] = []
    func testStarsUseFiveSymbolsWithOnePointHalfSteps() {
        for score in 0...10 {
            let symbols = OriginalWritingScoreView.symbols(for: score)
            XCTAssertEqual(symbols.count, 5)
            XCTAssertEqual(symbols.filter { $0 == "star.fill" }.count, score / 2)
            XCTAssertEqual(symbols.filter { $0 == "star.leadinghalf.filled" }.count, score % 2)
            XCTAssertEqual(symbols.filter { $0 == "star" }.count, 5 - (score + 1) / 2)
        }
        XCTAssertTrue(OriginalWritingScoreView.symbols(for: -1).isEmpty)
        XCTAssertTrue(OriginalWritingScoreView.symbols(for: 11).isEmpty)
    }

    @MainActor func testScoredSingleReplyStreamsCopiesAndNavigatesOnlyItsBody() {
        let session = makeSession()
        session.phase = .result
        session.usesGroupedWriteProtocol = true
        session.streamingMarkdown = "## Score\n10\n"
        session.refreshStreamingSelection()
        XCTAssertEqual(session.liveWriteSections.originalScore, 10)
        XCTAssertNil(session.candidateIndex)
        XCTAssertTrue(session.suggestion.isEmpty)
        session.streamingMarkdown! += "## General\nKeep **literal** text.\n## General Notes\n无需修改。"
        session.refreshStreamingSelection()
        for offset in [-1, 1, 1] { session.moveCandidate(offset) }
        XCTAssertEqual(session.candidateIndex, 0)
        XCTAssertEqual(session.suggestion, "Keep **literal** text.")
        XCTAssertEqual(session.liveWriteSections.finished, [true, false])
        XCTAssertNil(session.liveWriteSections.cards[1])
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        session.copy(to: board)
        XCTAssertEqual(board.string(forType: .string), "Keep **literal** text.")
    }

    @MainActor func testCompletedScoreDoesNotOverrideReturnedAnswers() throws {
        let session = makeSession()
        session.phase = .result
        session.input = "Original."
        session.result = try CloudAPIContract.parseContent("## Score\n10\n## General\nChanged.\n## General Notes\n说明。\n## Direction\n更自然\n## Alternative\nAnother.\n## Alternative Notes\n说明。", action: .writeEnglish)
        session.chooseCandidate(0)
        XCTAssertEqual(session.suggestion, "Changed.")
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 1)
        XCTAssertEqual(session.speechText, "Another.")
        session.result = try CloudAPIContract.parseContent("## Score\n9\n## General\nOnly answer.\n## General Notes\n说明。", action: .writeEnglish)
        session.chooseCandidate(0)
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 0)
        XCTAssertEqual(session.suggestion, "Only answer.")
    }

    func testScoredFallbackKeepsMetadataOutOfCopyableText() {
        let scoreOnly = BestEffortResult.make(content: "## Score\n10", action: .writeEnglish, plainWriteBodies: true)
        XCTAssertTrue(scoreOnly.candidates.isEmpty)
        XCTAssertEqual(scoreOnly.originalScore, 10)
        let partial = BestEffortResult.make(content: "## Score\n10\n## General\nChanged.\n## General Notes\n说明。", action: .writeEnglish, plainWriteBodies: true)
        XCTAssertEqual(partial.candidates, ["Changed."])
        XCTAssertEqual(partial.originalScore, 10)
        let invalid = BestEffortResult.make(content: "## Score\n11\n## General\nChanged.", action: .writeEnglish, plainWriteBodies: true)
        XCTAssertNil(invalid.originalScore)
        XCTAssertEqual(invalid.candidates, ["Changed."])
    }

    @MainActor func testGroupedStreamSelectionAndNotesNeverPolluteCopy() {
        let session = makeSession()
        session.phase = .result
        session.usesGroupedWriteProtocol = true
        session.streamingMarkdown = "## General\nKeep **literal** text.\n## General Notes\n- First explanation."
        session.refreshStreamingSelection()
        XCTAssertEqual(session.suggestion, "Keep **literal** text.")
        XCTAssertEqual(session.liveWriteSections.finished, [true, false])
        XCTAssertEqual(session.liveWriteSections.explanations[0], "- First explanation.")
        XCTAssertNil(session.liveWriteSections.cards[1])
        session.streamingMarkdown! += "\n## Direction\n更自然\n## Alternative\nSecond answer.\n## Alternative Notes\n- Second explanation."
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 1)
        XCTAssertEqual(session.suggestion, "Second answer.")
        XCTAssertEqual(session.liveWriteSections.finished, [true, true])
        XCTAssertEqual(session.liveWriteSections.explanations[1], "- Second explanation.")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        session.copy(to: board)
        XCTAssertEqual(board.string(forType: .string), "Second answer.")
    }

    func testGroupedFallbackKeepsExplanationPairedWithReceivedBody() {
        let partial = "## General\nKeep **literal** text.\n## General Notes\n- 中文说明。\n## Direction\n更自然\n## Alternative\nSecond"
        let result = BestEffortResult.make(content: partial, action: .writeEnglish, plainWriteBodies: true)
        XCTAssertEqual(result.candidates, ["Keep **literal** text.", "Second"])
        XCTAssertEqual(result.explanations, ["- 中文说明。", ""])
        XCTAssertTrue(result.summary.isEmpty)
        let early = BestEffortResult.make(content: "## General\nKeep **literal** text.", action: .writeEnglish, plainWriteBodies: true)
        XCTAssertEqual(early.candidates, ["Keep **literal** text."])
    }

    @MainActor func testGroupedFinalResultHasSeparateExplanationAndKeyboardTargets() {
        let session = makeSession()
        session.input = "Please helps."
        session.result = WritingFixture.result
        session.phase = .result
        session.chooseCandidate(0)
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 1)
        XCTAssertEqual(session.speechText, WritingFixture.result.candidates[1])
        XCTAssertFalse(session.suggestion.contains("调整措辞"))
        session.moveCandidate(-1)
        XCTAssertEqual(session.suggestion, WritingFixture.result.candidates[0])
    }

    @MainActor func testGroupedQuestionsKeepEachExplanationBesideItsAnswer() {
        let session = makeSession()
        session.input = "Original."
        session.result = WritingFixture.result
        session.phase = .result
        session.chooseCandidate(0)
        session.openQuestions()
        let context = session.questions.context
        let firstExplanation = context.range(of: WritingFixture.result.explanations[0])
        let secondAnswer = context.range(of: "Answer 2")
        XCTAssertNotNil(firstExplanation)
        XCTAssertNotNil(secondAnswer)
        if let firstExplanation, let secondAnswer {
            XCTAssertLessThan(firstExplanation.lowerBound, secondAnswer.lowerBound)
        }
    }

    @MainActor func testGrowingResultUsesNeverInsteadOfMouseOverridableHidden() {
        let session = makeSession()
        XCTAssertEqual(session.resultScrollIndicatorVisibility, .never)
        session.showsResultScrollIndicators = true
        XCTAssertEqual(session.resultScrollIndicatorVisibility, .automatic)
        session.showsResultScrollIndicators = false
        XCTAssertEqual(session.resultScrollIndicatorVisibility, .never)
    }

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites.removeAll()
        super.tearDown()
    }
    @MainActor func testCardObserverPassesThroughMouseDownAndPreservesTextSelection() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: window.contentLayoutRect)
        let text = NSTextView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
        text.string = "Select these words"; text.isEditable = false; text.isSelectable = true
        text.setSelectedRange(NSRange(location: 0, length: 6))
        root.addSubview(text)
        let observer = CardSelectionView(frame: text.frame)
        root.addSubview(observer)
        window.contentView = root
        var selections = 0
        observer.onSelect = { selections += 1 }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 40, y: 40),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        observer.observe(event)
        XCTAssertEqual(selections, 1)
        XCTAssertNil(observer.hitTest(NSPoint(x: 10, y: 10)), "Observer must never cover the selectable text")
        XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: 6))
        observer.isHidden = true
        observer.observe(event)
        XCTAssertEqual(selections, 1, "Hidden cards must not be selected")
        observer.isHidden = false
        let outsidePoint = observer.convert(NSPoint(x: observer.bounds.maxX + 50, y: observer.bounds.maxY + 50), to: nil)
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: outsidePoint,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        observer.observe(outside)
        XCTAssertEqual(selections, 1)
    }

    func testMarkdownUsesNativeBlockStructureAndInlineEmphasis() {
        let blocks = MarkdownDocument.blocks("## Notes\n\nA **bold** paragraph.\n\n1. first\n2. second\n   - nested\n\n> quote\n\n```swift\nlet x = 1\n```\n")
        XCTAssertEqual(blocks.first?.headingLevel, 2)
        XCTAssertEqual(String(blocks[1].text.characters), "A bold paragraph.")
        XCTAssertTrue(blocks[1].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertEqual(blocks[2].marker, "1.")
        XCTAssertEqual(blocks[3].marker, "2.")
        XCTAssertEqual(blocks[4].listDepth, 2)
        XCTAssertEqual(blocks[4].marker, "•")
        XCTAssertTrue(blocks[5].isQuote)
        XCTAssertTrue(blocks[6].isCode)
        XCTAssertFalse(blocks.contains { String($0.text.characters).contains("##") })
    }

    func testMarkdownTableGroupsCellsInRowsAndRendersDivider() {
        let blocks = MarkdownDocument.blocks("|Term|Meaning|\n|---|---|\n|**help**|帮助|\n\n---\n")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertTrue(blocks[0].isTableHeader)
        XCTAssertEqual(blocks[0].tableCells.map { String($0.characters) }, ["Term", "Meaning"])
        XCTAssertEqual(blocks[1].tableCells.map { String($0.characters) }, ["help", "帮助"])
        XCTAssertTrue(blocks[2].isDivider)
    }

    func testBestEffortKeepsDirectionOutOfCopyableAnswers() {
        let partial = "## General\nFirst **answer**.\n## Direction\n更适合协作\n## Alternative\nSecond *answer*."
        let result = BestEffortResult.make(content: partial, action: .writeEnglish)
        XCTAssertEqual(result.candidates, ["First answer.", "Second answer."])
        XCTAssertEqual(result.revisionDirection, "更适合协作")
        let oneAnswer = BestEffortResult.make(content: "## General\nFirst answer.\n## Direction\n更适合协作", action: .writeEnglish)
        XCTAssertEqual(oneAnswer.candidates, ["First answer."])
        let metadataOnly = BestEffortResult.make(content: "## Direction\n更适合协作", action: .writeEnglish)
        XCTAssertTrue(metadataOnly.candidates.isEmpty)
    }

    @MainActor func testStreamingSelectionDoesNotResetAndCopyTargetTracksDeltas() {
        let session = makeSession()
        session.phase = .result
        session.streamingMarkdown = "## General\nFirst **answer**.\n\n## Direction\n更自然\n## Alternative\nSecond"
        XCTAssertNil(session.candidateIndex)
        _ = session.liveWriteSections
        XCTAssertNil(session.candidateIndex, "Reading view state must not mutate selection")
        session.refreshStreamingSelection()
        XCTAssertEqual(session.candidateIndex, 0)
        session.chooseStreamingCandidate(1, plain: "Second")
        session.streamingMarkdown! += " answer.\n"
        session.refreshStreamingSelection()
        XCTAssertEqual(session.candidateIndex, 1)
        XCTAssertEqual(session.suggestion, "Second answer.")
        XCTAssertEqual(session.liveWriteSections.direction ?? session.result?.revisionDirection, "更自然")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        session.copy(to: board)
        XCTAssertEqual(board.string(forType: .string), "Second answer.")
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 1)
        session.moveCandidate(1)
        XCTAssertEqual(session.candidateIndex, 1)
    }

    @MainActor func testSelectedStreamingCardSurvivesFinalCommit() async throws {
        let suite = "ResultInteractionTests.\(UUID().uuidString)"
        suites.append(suite)
        let inference = PausedStreamingInference()
        let session = AssistantSession(preferences: Preferences(defaults: UserDefaults(suiteName: suite)!),
                                       accessibility: AccessibilityBridge(), inference: inference)
        session.input = "First answer."
        session.process()
        for _ in 0..<100 where inference.resume == nil { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertNotNil(inference.resume)
        XCTAssertEqual(session.candidateIndex, 0)
        session.chooseStreamingCandidate(1, plain: "Second answer.")
        inference.resume?.resume(returning: inference.content)
        inference.resume = nil
        for _ in 0..<100 where session.requestStartedAt != nil { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertNil(session.requestStartedAt)
        XCTAssertFalse(session.isStreaming)
        XCTAssertEqual(session.candidateIndex, 1)
        XCTAssertEqual(session.suggestion, "Second answer.")
        XCTAssertEqual(session.liveWriteSections.direction ?? session.result?.revisionDirection, "更自然")
    }

    @MainActor func testGroupedReplyLayoutSizesBothBodiesWithoutNestedScrollers() async throws {
        let session = makeSession()
        session.input = "Please helps me fix this bug."
        session.phase = .result
        session.result = WritingFixture.result
        session.chooseCandidate(0)
        let hosting = NSHostingView(rootView: WritingResultsView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.frame = window.contentLayoutRect
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        hosting.layoutSubtreeIfNeeded()
        func bodies(_ view: NSView) -> [DiffDemoLayeredDocument] {
            (view as? DiffDemoLayeredDocument).map { [$0] } ?? view.subviews.flatMap(bodies)
        }
        let texts = bodies(hosting)
        XCTAssertEqual(texts.count, 2)
        XCTAssertEqual(Set(texts.map(\.revisedText)), Set(WritingFixture.result.candidates))
        XCTAssertTrue(texts.allSatisfy { $0.bounds.height > 20 && !($0.superview is NSClipView) })
        XCTAssertNotNil(session.resultMeasure)
        if let measure = session.resultMeasure {
            XCTAssertGreaterThan(measure.content, texts.map { $0.bounds.height }.reduce(0, +),
                                 "Reply explanations must contribute to outer scroll content height")
        }
    }

    @MainActor func testBothViewsUseSharedMarkdownAndBodyObserverIsActuallyInstalled() async throws {
        let session = makeSession()
        session.phase = .result
        session.result = ModelResult(candidates: ["First answer.", "Second answer.", "Third answer."],
            summary: "## Notes\n\n1. **help** means 帮助.\n2. Keep it short.\n\n> A useful quote.")
        session.chooseCandidate(0)
        let hosting = NSHostingView(rootView: WritingResultsView(session: session).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.frame = window.contentLayoutRect
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        hosting.layoutSubtreeIfNeeded()
        func observers(_ view: NSView) -> [CardSelectionView] {
            (view as? CardSelectionView).map { [$0] } ?? view.subviews.flatMap(observers)
        }
        let cards = observers(hosting).sorted { $0.convert($0.bounds.origin, to: hosting).y < $1.convert($1.bounds.origin, to: hosting).y }
        XCTAssertEqual(cards.count, 3)
        let card = try XCTUnwrap(cards.dropFirst().first)
        XCTAssertGreaterThan(card.bounds.width, 400)
        let location = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertEqual(card.window, window)
        card.observe(event)
        XCTAssertEqual(session.candidateIndex, 1)
        if let directory = ProcessInfo.processInfo.environment["ENGLISHCOMPASS_UI_PREVIEW"] {
            try await save(hosting, to: directory + "/write-notes.png")
            session.action = .understandEnglish
            session.input = "Please help me fix this bug."
            session.result = ModelResult(candidates: ["请帮我修复问题。"], summary: "### 用法\n\n- **help** 后可以省略 `to`。\n- 比较这两种写法：\n  - help me fix\n  - help me to fix\n\n> 意思相同。")
            session.chooseCandidate(0)
            let understanding = NSHostingView(rootView: UnderstandingResultView(session: session).background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = understanding; understanding.frame = window.contentLayoutRect
            try await save(understanding, to: directory + "/understand-notes.png")
            let picker = NSHostingView(rootView: ModelSettingsView(preferences: session.preferences).padding(20)
                .frame(width: 500, height: 150, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = picker
            window.setContentSize(NSSize(width: 500, height: 150))
            picker.frame = window.contentLayoutRect
            try await save(picker, to: directory + "/model-picker.png")
        }
    }

    @MainActor private func save(_ view: NSView, to path: String) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
    @MainActor private func makeSession() -> AssistantSession {
        let suite = "ResultInteractionTests.\(UUID().uuidString)"
        suites.append(suite)
        return AssistantSession(preferences: Preferences(defaults: UserDefaults(suiteName: suite)!),
                         accessibility: AccessibilityBridge(), inference: InferenceService(credential: { "synthetic" }))
    }
}
