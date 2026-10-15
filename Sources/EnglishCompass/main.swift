import AppKit
import AssistantCore

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--configure-cloud") {
        // The authorized installer passes a key through stdin, never process arguments.
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 4096, let key = String(data: data, encoding: .utf8) else {
                throw AssistantFailure.cloudKeyMissing
            }
            try CloudCredentialStore.save(key)
            _ = Preferences()
            print("event=cloud_configured model=qwen3.7-flash mode=non-thinking")
            exit(0)
        } catch {
            print("event=cloud_configuration_failed")
            exit(1)
        }
    }
    let app = NSApplication.shared
    if CommandLine.arguments.contains("--lab") {
        // Local test window only: no shortcuts, status item, capture or Keychain.
        let lab = LabAppDelegate()
        app.delegate = lab
        withExtendedLifetime(lab) { app.run() }
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
