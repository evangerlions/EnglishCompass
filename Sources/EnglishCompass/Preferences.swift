import Foundation
import AssistantCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let write = Shortcut(keyCode: 14, modifiers: 6144, label: "Control + Option + E")
    static let understand = Shortcut(keyCode: 15, modifiers: 6144, label: "Control + Option + R")
    static let speak = Shortcut(keyCode: 1, modifiers: 6144, label: "Control + Option + S")
    /// Previous default, kept only to migrate users who never customized it.
    static let legacyUnderstand = Shortcut(keyCode: 8, modifiers: 6144, label: "Control + Option + C")
}

/// The three global shortcuts the app registers.
enum ShortcutKind: String, CaseIterable {
    case write, understand, speak
    var title: String {
        switch self {
        case .write: AssistantAction.writeEnglish.title
        case .understand: AssistantAction.understandEnglish.title
        case .speak: "Read Aloud"
        }
    }
    var detail: String {
        switch self {
        case .write: "Polish a draft or turn it into English."
        case .understand: "Translate selected English into Chinese."
        case .speak: "Read the selected English aloud. Press again to stop."
        }
    }
    var defaultShortcut: Shortcut {
        switch self {
        case .write: .write
        case .understand: .understand
        case .speak: .speak
        }
    }
    var action: AssistantAction? {
        switch self {
        case .write: .writeEnglish
        case .understand: .understandEnglish
        case .speak: nil
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    @Published var writeInstructions: String { didSet { save() } }
    @Published var understandInstructions: String { didSet { save() } }
    @Published var diagnostics: Bool { didSet { save() } }
    @Published var writeShortcut: Shortcut { didSet { save() } }
    @Published var understandShortcut: Shortcut { didSet { save() } }
    @Published var speakShortcut: Shortcut { didSet { save() } }
    /// English accent for speech: `en-US` or `en-GB`.
    @Published var speechAccent: String { didSet { save() } }
    /// Voice identifier; empty means the best installed voice for the accent.
    @Published var speechVoice: String { didSet { save() } }
    /// AVSpeechUtterance rate, kept in a comfortable 0.30–0.60 range.
    @Published var speechRate: Float { didSet { save() } }
    static let defaultSpeechRate: Float = 0.47
    static let speechAccents = ["en-US", "en-GB"]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Retire mode settings and migrate the old shared prompt into both
        // action-specific fields without losing the user's existing preference.
        for key in ["provider", "writeMode", "understandMode"] { defaults.removeObject(forKey: key) }
        let legacyInstructions: String
        if let saved = defaults.string(forKey: "additionalInstructions") {
            legacyInstructions = saved
        } else {
            let oldTerms = (defaults.string(forKey: "terms") ?? "")
                .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            legacyInstructions = oldTerms.isEmpty ? "" : "Keep these terms unchanged: " + oldTerms.joined(separator: ", ")
        }
        writeInstructions = defaults.object(forKey: "writeInstructions") == nil
            ? legacyInstructions : (defaults.string(forKey: "writeInstructions") ?? "")
        understandInstructions = defaults.object(forKey: "understandInstructions") == nil
            ? legacyInstructions : (defaults.string(forKey: "understandInstructions") ?? "")
        diagnostics = defaults.bool(forKey: "diagnostics")
        writeShortcut = Self.decode(defaults, "writeShortcut") ?? .write
        let savedUnderstand: Shortcut? = Self.decode(defaults, "understandShortcut")
        // Every save() persists all shortcuts, so a stored value equal to the old
        // default is not a deliberate choice; move it to the new default.
        understandShortcut = (savedUnderstand == nil || savedUnderstand == .legacyUnderstand) ? .understand : savedUnderstand!
        speakShortcut = Self.decode(defaults, "speakShortcut") ?? .speak
        let accent = defaults.string(forKey: "speechAccent") ?? "en-US"
        speechAccent = Self.speechAccents.contains(accent) ? accent : "en-US"
        speechVoice = defaults.string(forKey: "speechVoice") ?? ""
        let rate = (defaults.object(forKey: "speechRate") as? NSNumber)?.floatValue ?? Self.defaultSpeechRate
        speechRate = min(max(rate, 0.30), 0.60)
        defaults.set(try? JSONEncoder().encode(understandShortcut), forKey: "understandShortcut")
        defaults.set(writeInstructions, forKey: "writeInstructions")
        defaults.set(understandInstructions, forKey: "understandInstructions")
        defaults.removeObject(forKey: "additionalInstructions")
        defaults.removeObject(forKey: "terms")
    }
    func instructions(for action: AssistantAction) -> String {
        action == .writeEnglish ? writeInstructions : understandInstructions
    }
    func shortcut(for kind: ShortcutKind) -> Shortcut {
        switch kind {
        case .write: writeShortcut
        case .understand: understandShortcut
        case .speak: speakShortcut
        }
    }
    var allShortcuts: [ShortcutKind: Shortcut] {
        Dictionary(uniqueKeysWithValues: ShortcutKind.allCases.map { ($0, shortcut(for: $0)) })
    }
    func setShortcuts(_ values: [ShortcutKind: Shortcut]) {
        if let value = values[.write] { writeShortcut = value }
        if let value = values[.understand] { understandShortcut = value }
        if let value = values[.speak] { speakShortcut = value }
    }
    private static func decode(_ defaults: UserDefaults, _ key: String) -> Shortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }
    private func save() {
        defaults.set(writeInstructions, forKey: "writeInstructions")
        defaults.set(understandInstructions, forKey: "understandInstructions")
        defaults.set(diagnostics, forKey: "diagnostics")
        defaults.set(try? JSONEncoder().encode(writeShortcut), forKey: "writeShortcut")
        defaults.set(try? JSONEncoder().encode(understandShortcut), forKey: "understandShortcut")
        defaults.set(try? JSONEncoder().encode(speakShortcut), forKey: "speakShortcut")
        defaults.set(speechAccent, forKey: "speechAccent")
        defaults.set(speechVoice, forKey: "speechVoice")
        defaults.set(speechRate, forKey: "speechRate")
    }
}
