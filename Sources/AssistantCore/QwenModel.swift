import Foundation

/// Small curated text-model picker, not a performance ranking. Keep the existing
/// default; selection is explicit. Availability depends on the user's account.
/// Model IDs: https://help.aliyun.com/en/model-studio/qwen-api-via-openai-chat-completions
public enum QwenModel: String, CaseIterable, Identifiable {
    case flash37 = "qwen3.7-flash"
    case flash38 = "qwen3.8-flash"
    case plus37 = "qwen3.7-plus"
    case max38 = "qwen3.8-max"
    case max37 = "qwen3.7-max"
    case flash36 = "qwen3.6-flash"
    case plus36 = "qwen3.6-plus"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flash37: "Qwen3.7 Flash"
        case .flash38: "Qwen3.8 Flash"
        case .plus37: "Qwen3.7 Plus"
        case .max38: "Qwen3.8 Max"
        case .max37: "Qwen3.7 Max"
        case .flash36: "Qwen3.6 Flash"
        case .plus36: "Qwen3.6 Plus"
        }
    }
}
