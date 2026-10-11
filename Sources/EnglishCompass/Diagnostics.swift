import Foundation
import OSLog

enum Diagnostics {
    static let logger = Logger(subsystem: "com.zook.EnglishCompass", category: "workflow")
    // Callers may supply only controlled enums/identifiers, never user/model text.
    static func event(_ name: String, action: String = "none", mode: String = "none") {
        logger.info("event=\(name, privacy: .public) action=\(action, privacy: .public) mode=\(mode, privacy: .public)")
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            print("event=\(name) action=\(action) mode=\(mode)")
        }
    }
    static func metrics(elapsed: TimeInterval, characters: Int) {
        guard UserDefaults.standard.bool(forKey: "diagnostics") else { return }
        let bucket = characters < 100 ? "short" : characters < 1000 ? "medium" : "long"
        logger.info("event=inference_metrics duration_ms=\(Int(elapsed * 1000)) length_bucket=\(bucket, privacy: .public)")
    }
}
