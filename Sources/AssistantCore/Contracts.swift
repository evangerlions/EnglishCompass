import Foundation

public enum AssistantAction: String, Codable, CaseIterable, Sendable {
    case writeEnglish = "write_english"
    case understandEnglish = "understand_english"
    public var title: String { self == .writeEnglish ? "Write in English" : "Understand English" }
}

public struct ModelResult: Codable, Equatable, Sendable {
    public var candidates: [String]
    public var explanations: [String]
    public var summary: String
    public var highlights: [[String]]
    public var markdownCandidates: [String]
    public init(candidates: [String], explanations: [String] = [], summary: String = "", highlights: [[String]] = [], markdownCandidates: [String] = []) {
        self.candidates = candidates
        self.explanations = explanations
        self.summary = summary
        self.highlights = highlights
        self.markdownCandidates = markdownCandidates
    }
    public func validated() throws -> ModelResult {
        let rich = candidates.count == 3
        guard (1...3).contains(candidates.count), explanations.count <= (rich ? 3 : 2),
              !rich || (explanations.count == 3 && explanations.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) && (markdownCandidates.count == 3 || (!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && highlights.count == 3))),
              markdownCandidates.isEmpty || (markdownCandidates.count == candidates.count && markdownCandidates.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })),
              highlights.isEmpty || (highlights.count == candidates.count && highlights.enumerated().allSatisfy { index, terms in
                  terms.count <= 3 && terms.allSatisfy { !$0.isEmpty && candidates[index].contains($0) }
              }),
              candidates.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              (candidates + explanations + [summary] + highlights.flatMap { $0 } + markdownCandidates).allSatisfy({ !$0.contains("<think") && !$0.contains("</think") })
        else { throw AssistantFailure.invalidResult }
        return self
    }
}

/// Carries the raw provider response body when a 200 payload fails content parsing,
/// so the UI can offer a collapsible, colorized debug view. Never logged or persisted.
public struct InvalidResultError: Error, LocalizedError, Sendable {
    public let underlying: AssistantFailure
    public let rawResponse: String
    public init(underlying: AssistantFailure, rawResponse: String) {
        self.underlying = underlying
        self.rawResponse = rawResponse
    }
    public var errorDescription: String? { underlying.errorDescription }
}

public enum AssistantFailure: String, Error, LocalizedError, Sendable {
    case permission
    case noText = "no_text"
    case selectText = "select_text"
    case secureField = "secure_field"
    case changedDraft = "changed_draft"
    case changedTarget = "changed_target"
    case unsupportedWriteback = "unsupported_writeback"
    case invalidResult = "invalid_result"
    case contextLimit = "context_limit"
    case cancelled
    case timedOut = "timed_out"
    case shortcutConflict = "shortcut_conflict"
    case cloudKeyMissing = "cloud_key_missing"
    case cloudKeychainAccess = "cloud_keychain_access"
    case cloudAuth = "cloud_auth"
    case cloudRateLimit = "cloud_rate_limit"
    case cloudUnavailable = "cloud_unavailable"
    public var errorDescription: String? {
        switch self {
        case .permission: return "Allow Accessibility access to read and replace text. Manual paste remains available."
        case .noText: return "No editable draft was available. Paste text here instead."
        case .selectText: return "Select the English text first. Terminal history is never read automatically."
        case .secureField: return "Password and secure fields are never read."
        case .changedDraft: return "The original draft has changed. Copy the suggestion or check the draft again."
        case .changedTarget: return "The original app or text field changed. Copy the suggestion instead."
        case .unsupportedWriteback: return "This app does not support precise replacement. Copy the suggestion instead."
        case .invalidResult: return "The model returned an incomplete or invalid result. Nothing was replaced."
        case .contextLimit: return "Select a shorter passage (maximum 16,000 characters)."
        case .cancelled: return "Cancelled. Your original text is unchanged."
        case .timedOut: return "Inference timed out. Your original text is unchanged."
        case .shortcutConflict: return "The shortcut could not be registered. Choose another combination."
        case .cloudKeyMissing: return "Add your Bailian API key in Settings. Nothing was uploaded."
        case .cloudKeychainAccess: return "Authorize English Compass to use its saved API key in macOS Keychain."
        case .cloudAuth: return "Bailian rejected the API key. Check it in Settings."
        case .cloudRateLimit: return "Bailian is rate-limiting requests. Try again later."
        case .cloudUnavailable: return "Bailian could not be reached. No automatic fallback was attempted."
        }
    }
}

public struct DraftSnapshot: Equatable, Sendable {
    public let fullText: String
    public let range: NSRange
    public init(fullText: String, range: NSRange) throws {
        let length = (fullText as NSString).length
        guard range.location != NSNotFound, range.location <= length,
              range.length <= length - range.location else { throw AssistantFailure.noText }
        self.fullText = fullText
        self.range = range
    }
    public var input: String { (fullText as NSString).substring(with: range) }
    public func replacing(with text: String, current: String) throws -> String {
        guard current.utf16.elementsEqual(fullText.utf16) else { throw AssistantFailure.changedDraft }
        return (fullText as NSString).replacingCharacters(in: range, with: text)
    }
}
