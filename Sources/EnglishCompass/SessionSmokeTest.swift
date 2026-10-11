import AppKit
import AssistantCore

/// Exercises the actual session controller with explicitly labelled fixtures.
/// It does not validate model output or cross-app AX compatibility.
@MainActor
enum SessionSmokeTest {
    static func run(_ session: AssistantSession) async -> Bool {
        _ = session.begin(.writeEnglish, capture: false)
        session.input = "Please helps me fix this bug."
        session.process()
        guard session.phase == .processing else { return false }
        try? await Task.sleep(for: .milliseconds(1200))
        guard session.phase == .result, session.suggestion == "Please help me fix this bug.", !session.canReplace else { return false }
        session.cancel()
        guard session.input.isEmpty, session.suggestion.isEmpty, session.result == nil else { return false }
        _ = session.begin(.writeEnglish, capture: false)
        session.input = "Cancelled fixture"
        session.process()
        session.cancel(close: false)
        _ = session.begin(.understandEnglish, capture: false)
        session.input = "Please help me fix this bug."
        session.process()
        try? await Task.sleep(for: .milliseconds(1200))
        guard session.phase == .result, session.action == .understandEnglish,
              session.suggestion == "请帮我修复这个问题。", !session.canReplace else { return false }
        session.cancel()
        return true
    }
}
