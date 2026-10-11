import SwiftUI

struct CloudSettingsView: View {
    var onKeySaved: (String) -> Void = { _ in }
    @State private var key = ""
    @State private var stored = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bailian API key").font(.system(size: 13, weight: .semibold))
                Spacer()
                Label(stored ? "Saved in Keychain" : "Not configured", systemImage: stored ? "checkmark.circle" : "key")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                SecureField(stored ? "Enter a replacement API key" : "Paste your API key", text: $key)
                    .textFieldStyle(.roundedBorder).controlSize(.large).accessibilityIdentifier("cloud_api_key")
                Button("Save key") {
                    do {
                        try CloudCredentialStore.save(key)
                        onKeySaved(key)
                        stored = true; key = ""; message = "Key saved in Keychain."
                    } catch { message = "Could not save the API key. Check Keychain access." }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Stored securely on this Mac. Read once per session, then kept in memory until you quit.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            if !message.isEmpty { Text(message).font(.caption) }
        }.onAppear { stored = CloudCredentialStore.containsKey }
    }
}
