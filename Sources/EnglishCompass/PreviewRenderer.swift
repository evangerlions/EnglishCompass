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
        session.input = "I don't want to inertia scroll."
        session.result = ModelResult(candidates: ["I don't want inertial scrolling."])
        session.chooseCandidate(0)
        try save(ResultView(session: session), size: NSSize(width: 540, height: 300), to: directory.appendingPathComponent("single-answer-fixture.png"))
        session.phase = .error; session.message = AssistantFailure.cloudUnavailable.localizedDescription
        try save(ResultView(session: session), size: NSSize(width: 540, height: 400), to: directory.appendingPathComponent("error-fixture.png"))
        session.action = .understandEnglish; session.result = ModelResult(candidates: ["请帮我修复这个问题。"])
        session.chooseCandidate(0); session.phase = .result; session.message = ""
        try save(ResultView(session: session), size: NSSize(width: 540, height: 390), to: directory.appendingPathComponent("translation-fixture.png"))
        try save(SettingsView(preferences: preferences, accessibility: accessibility,
                              onShortcut: { _, _ in nil }), size: NSSize(width: 820, height: 620),
                 to: directory.appendingPathComponent("settings-fixture.png"))
        session.cancel()
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
