import SwiftUI
import AssistantCore

/// The same persisted setting is used by Settings and the Lab inspector.
struct WritingLanguageSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Writing target language", selection: $preferences.writingLanguage) {
                ForEach(WritingLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .accessibilityIdentifier("writing_language_picker")
            Text("Translate into this language, or refine text already written in it. Applies to the next request.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Directions and explanations stay in Chinese. Understand English still translates into Chinese.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
