import SwiftUI

struct SettingsVersionView: View {
    private var versionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return "Version unavailable"
        }
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else {
            return "Version \(version)"
        }
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Text(versionLabel)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .accessibilityIdentifier("settings_version")
    }
}
