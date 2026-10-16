import SwiftUI
import AssistantCore

/// Shared by release Settings and Lab. Changing this affects the next request,
/// never an already-running stream. Each mode keeps its own defaults suite.
struct ModelSettingsView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Model", selection: $preferences.model) {
                ForEach(QwenModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .accessibilityIdentifier("qwen_model_picker")
            Text(preferences.model.rawValue)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Text("Write & Understand · Non-thinking · Applies to the next request")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
