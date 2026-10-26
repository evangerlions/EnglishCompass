import Foundation

/// Initial top-ten catalog plus additional user-requested languages.
public enum WritingLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en", chinese = "zh", hindi = "hi", spanish = "es", arabic = "ar"
    case french = "fr", bengali = "bn", portuguese = "pt", indonesian = "id", urdu = "ur"
    case japanese = "ja", korean = "ko"
    public var id: String { rawValue }
    public var name: String { details.name }
    public var displayName: String { "\(details.chinese) · \(details.native)" }
    public var chineseName: String { details.chinese }
    public var speechLocale: String { details.locale }
    public var example: String { details.example }
    public var isRightToLeft: Bool { self == .arabic || self == .urdu }

    private var details: (name: String, chinese: String, native: String, locale: String, example: String) {
        switch self {
        case .english: ("English", "英语", "English", "en-US", "Hello, I'm Lin Chen.")
        case .chinese: ("Simplified Mandarin Chinese", "中文（简体）", "简体中文", "zh-CN", "你好，我叫林晨。")
        case .hindi: ("Hindi", "印地语", "हिन्दी", "hi-IN", "नमस्ते, मेरा नाम लिन चेन है।")
        case .spanish: ("Spanish", "西班牙语", "Español", "es-ES", "Hola, soy Lin Chen.")
        case .arabic: ("Modern Standard Arabic", "阿拉伯语", "العربية", "ar-SA", "مرحبًا، أنا لين تشن.")
        case .french: ("French", "法语", "Français", "fr-FR", "Bonjour, je m’appelle Lin Chen.")
        case .bengali: ("Bengali", "孟加拉语", "বাংলা", "bn-BD", "হ্যালো, আমার নাম লিন চেন।")
        case .portuguese: ("Portuguese", "葡萄牙语", "Português", "pt-BR", "Olá, sou Lin Chen.")
        case .indonesian: ("Indonesian", "印尼语", "Bahasa Indonesia", "id-ID", "Halo, saya Lin Chen.")
        case .urdu: ("Urdu", "乌尔都语", "اردو", "ur-PK", "ہیلو، میرا نام لن چن ہے۔")
        case .japanese: ("Japanese", "日语", "日本語", "ja-JP", "こんにちは、林晨と申します。")
        case .korean: ("Korean", "韩语", "한국어", "ko-KR", "안녕하세요, 저는 린천입니다.")
        }
    }
}
