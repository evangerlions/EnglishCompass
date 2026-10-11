import Foundation
import AssistantCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let write = Shortcut(keyCode: 14, modifiers: 6144, label: "Control + Option + E")
    static let understand = Shortcut(keyCode: 8, modifiers: 6144, label: "Control + Option + C")
}

@MainActor
final class Preferences: ObservableObject {
    @Published var additionalInstructions: String { didSet { save() } }
    @Published var diagnostics: Bool { didSet { save() } }
    @Published var writeShortcut: Shortcut { didSet { save() } }
    @Published var understandShortcut: Shortcut { didSet { save() } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Retire mode settings and migrate the old list into a normal prompt preference.
        for key in ["provider", "writeMode", "understandMode"] { defaults.removeObject(forKey: key) }
        if let saved = defaults.string(forKey: "additionalInstructions") {
            additionalInstructions = saved
        } else {
            let oldTerms = (defaults.string(forKey: "terms") ?? "")
                .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let migrated = oldTerms.isEmpty ? "" : "Keep these terms unchanged: " + oldTerms.joined(separator: ", ")
            additionalInstructions = migrated
            defaults.set(migrated, forKey: "additionalInstructions")
        }
        defaults.removeObject(forKey: "terms")
        diagnostics = defaults.bool(forKey: "diagnostics")
        writeShortcut = defaults.data(forKey: "writeShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .write
        understandShortcut = defaults.data(forKey: "understandShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .understand
    }
    private func save() {
        defaults.set(additionalInstructions, forKey: "additionalInstructions")
        defaults.set(diagnostics, forKey: "diagnostics")
        defaults.set(try? JSONEncoder().encode(writeShortcut), forKey: "writeShortcut")
        defaults.set(try? JSONEncoder().encode(understandShortcut), forKey: "understandShortcut")
    }
}
