import AppKit
import SwiftUI
import AssistantCore

/// Fixture-only visual snapshots. These are not live cross-app E2E evidence.
@MainActor
enum PreviewRenderer {
    static func render(to directory: URL, session: AssistantSession, preferences: Preferences,
                       accessibility: AccessibilityBridge, inference: InferenceService) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session.begin(.writeEnglish, capture: false)
        try save(ResultView(session: session), size: NSSize(width: 540, height: 360), to: directory.appendingPathComponent("input-fixture.png"))
        session.phase = .processing
        try save(ResultView(session: session), size: NSSize(width: 540, height: 310), to: directory.appendingPathComponent("loading-fixture.png"))
        session.input = "Please helps me fix this bug."
        session.result = WritingFixture.result
        session.chooseCandidate(0); session.phase = .result
        try save(ResultView(session: session), size: NSSize(width: 540, height: 500), to: directory.appendingPathComponent("result-fixture.png"))
        // Fitted heights: the same measurement loop the live panel uses.
        try saveFitted(session, to: directory.appendingPathComponent("fitted-normal.png"))
        let long = String(repeating: "This sentence is deliberately long so the panel must reach its maximum height and scroll. ", count: 4)
        session.result = ModelResult(candidates: [long, long, long],
                                     explanations: ["很长的通用版本。", "很长的口语版本。", "很长的学术版本。"],
                                     summary: "用于验证内容超过最大高度时窗口停在上限并可以滚动。")
        session.chooseCandidate(0)
        try saveFitted(session, to: directory.appendingPathComponent("fitted-long.png"))
        session.result = WritingFixture.result; session.chooseCandidate(0)
        session.input = "I don't want to inertia scroll."
        session.result = ModelResult(candidates: ["I don't want inertial scrolling."])
        session.chooseCandidate(0)
        try save(ResultView(session: session), size: NSSize(width: 540, height: 300), to: directory.appendingPathComponent("single-answer-fixture.png"))
        try saveFitted(session, to: directory.appendingPathComponent("fitted-single.png"))
        session.phase = .error; session.message = AssistantFailure.cloudUnavailable.localizedDescription
        try save(ResultView(session: session), size: NSSize(width: 540, height: 400), to: directory.appendingPathComponent("error-fixture.png"))
        session.action = .understandEnglish
        session.result = ModelResult(candidates: ["医用与呼吸防护口罩"],
                                     summary: "- **Medical masks**：医用口罩，常指医用外科或一次性医用口罩。\n- **Respiratory masks**：呼吸防护口罩，强调颗粒物防护，如 N95/KN95。",
                                     markdownCandidates: ["医用与**呼吸防护口罩**"])
        session.chooseCandidate(0); session.phase = .result; session.message = ""
        try save(ResultView(session: session), size: NSSize(width: 540, height: 390), to: directory.appendingPathComponent("translation-fixture.png"))
        try save(SettingsView(preferences: preferences, accessibility: accessibility,
                              onShortcut: { _, _ in nil }), size: NSSize(width: 820, height: 620),
                 to: directory.appendingPathComponent("settings-fixture.png"))
        session.cancel()
    }
    /// Starts at the default height and applies PanelSizing to the measured
    /// overflow until it settles, then saves and prints the final height.
    private static func saveFitted(_ session: AssistantSession, to url: URL) throws {
        let view = NSHostingView(rootView: ResultView(session: session))
        var height = PanelSizing.defaultHeight
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PanelSizing.width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        for _ in 0..<8 {
            view.frame = NSRect(x: 0, y: 0, width: PanelSizing.width, height: height)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard let next = PanelSizing.fittedHeight(current: height, overflow: session.resultOverflow,
                                                      screenHeight: 1000) else { break }
            height = next
        }
        print("event=fitted_height file=\(url.lastPathComponent) height=\(Int(height)) overflow=\(Int(session.resultOverflow))")
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
    private static func save<Content: View>(_ content: Content, size: NSSize, to url: URL) throws {
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
