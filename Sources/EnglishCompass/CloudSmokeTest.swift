import Foundation
import AssistantCore

/// Explicit synthetic-only acceptance path through native HTTPS and Keychain.
@MainActor
enum CloudSmokeTest {
    static func run(_ inference: InferenceService) async -> Bool {
        defer { inference.cancel() }
        do {
            let started = Date()
            let written = try await inference.infer(text: "Please helps me fix this bug.", action: .writeEnglish,
                                                    additionalInstructions: "")
            guard written.candidates.count == 3, written.candidates[0] == "Please help me fix this bug." else { return false }
            print("event=cloud_write_smoke_passed elapsed_seconds=\(Date().timeIntervalSince(started))")
            let understood = try await inference.infer(text: "Do not delete the file.", action: .understandEnglish,
                                                       additionalInstructions: "")
            guard understood.candidates.count == 1,
                  understood.candidates[0].contains("不"), understood.candidates[0].contains("删除") else { return false }
            print("event=cloud_understand_smoke_passed")
            return true
        } catch {
            print("event=cloud_smoke_failed")
            return false
        }
    }
}
