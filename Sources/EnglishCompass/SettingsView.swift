import SwiftUI
import AppKit
import ServiceManagement
import AssistantCore

private enum SettingsPage: String, CaseIterable, Identifiable {
    case shortcuts = "Shortcuts", model = "Model & API", instructions = "Instructions", privacy = "Privacy & access"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .shortcuts: "keyboard"
        case .model: "network"
        case .instructions: "text.alignleft"
        case .privacy: "lock"
        }
    }
    var subtitle: String {
        switch self {
        case .shortcuts: "A little less friction. In every app."
        case .model: "Fast answers, powered by your own API key."
        case .instructions: "Make the assistant sound more like you."
        case .privacy: "You decide what the assistant can access."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let accessibility: AccessibilityBridge
    let onShortcut: (AssistantAction, Shortcut) -> String?
    var onKeySaved: (String) -> Void = { _ in }
    @State private var page: SettingsPage = .shortcuts
    @State private var status = ""
    @State private var trusted = false
    @State private var login = false
    private let accent = Color(red: 0.08, green: 0.43, blue: 0.40)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(page.rawValue).font(.system(size: 25, weight: .semibold)).tracking(-0.5)
                    Text(page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(30)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .shortcuts: shortcutsContent
                        case .model: modelContent
                        case .instructions: instructionsContent
                        case .privacy: privacyContent
                        }
                        if !status.isEmpty {
                            Label(status, systemImage: "info.circle")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings_status")
                        }
                    }.padding(.horizontal, 30).padding(.bottom, 28)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 820, height: 620)
        .tint(accent)
        .onAppear { refreshPermissions(); login = SMAppService.mainApp.status == .enabled }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent).frame(width: 38, height: 38)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("English Compass").font(.system(size: 13, weight: .semibold))
                    Text("Your words, refined.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 34)
            Text("SETTINGS").font(.system(size: 10, weight: .semibold)).tracking(1.3)
                .foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 10)
            ForEach(SettingsPage.allCases) { item in
                Button {
                    page = item; status = ""
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).frame(width: 18)
                        Text(item.rawValue).font(.system(size: 13, weight: page == item ? .semibold : .medium))
                        Spacer()
                    }.foregroundStyle(page == item ? accent : Color.primary)
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(page == item ? accent.opacity(0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.bottom, 4)
                    .accessibilityIdentifier("settings_nav_" + item.id)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Spacer()
            Divider().padding(.bottom, 15)
            Label("Nothing is auto-sent", systemImage: "checkmark.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text("Review first. Replace when ready.")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 5)
        }.padding(20).frame(width: 218)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            surface {
                shortcutRow(.writeEnglish, preferences.writeShortcut, detail: "Polish a draft or turn it into English.")
                Divider().padding(.vertical, 12)
                shortcutRow(.understandEnglish, preferences.understandShortcut, detail: "Translate selected English into Chinese.")
            }
            HStack {
                Text("Click a shortcut to record a new combination.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    if let error = onShortcut(.writeEnglish, .write) { status = error }
                    if let error = onShortcut(.understandEnglish, .understand) { status = error }
                }.controlSize(.small)
            }
            surface {
                Toggle(isOn: $login) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Start with your Mac").font(.system(size: 13, weight: .medium))
                        Text("Keep the assistant within reach in the menu bar.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch).onChange(of: login) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        login = SMAppService.mainApp.status == .enabled
                        status = "Could not update launch at login. Run the app from a stable location."
                    }
                }
            }
            Text("If another app uses the same shortcut, choose a different combination.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            surface {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Qwen3.7 Flash").font(.system(size: 17, weight: .semibold))
                        Text("Alibaba Cloud Bailian / Beijing").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Non-thinking").font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(accent.opacity(0.08), in: Capsule())
                }
            }
            surface { CloudSettingsView(onKeySaved: onKeySaved) }
            Label("Your key. Your usage.", systemImage: "key")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private var instructionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Additional instructions").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Saved automatically").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    NativeTextEditor(text: $preferences.additionalInstructions,
                                     placeholder: "Use concise, natural English.\nKeep the tone friendly and professional.",
                                     fontSize: 13, identifier: "additional_instructions", label: "Additional instructions")
                        .frame(height: 190)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10)))
                    HStack {
                        Text("Applies to writing and translation.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { preferences.additionalInstructions = "" }
                            .controlSize(.small).disabled(preferences.additionalInstructions.isEmpty)
                    }
                }
            }
            Text("Stored on this Mac and included in each model request. Don't enter passwords or API keys here. Task and safety rules still apply.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            surface {
                VStack(alignment: .leading, spacing: 14) {
                    Label(trusted ? "Accessibility enabled" : "Accessibility needed",
                          systemImage: trusted ? "checkmark.circle.fill" : "lock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(trusted ? accent : Color.primary)
                    Text("Needed to read selected text and replace drafts in other apps. You always review before replacing.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    HStack {
                        if !trusted {
                            Button("Allow access") { accessibility.requestPermission(); refreshPermissions() }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Open system settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }.controlSize(.regular)
                }
            }
            surface {
                VStack(alignment: .leading, spacing: 16) {
                    Label("No local text history", systemImage: "text.badge.checkmark")
                        .font(.system(size: 13, weight: .medium))
                    Text("Drafts and translations are not saved. The selected text and additional instructions are sent to Bailian; nothing is automatically submitted to the source app.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    Divider()
                    Toggle("Diagnostic metadata", isOn: $preferences.diagnostics).toggleStyle(.switch)
                        .font(.system(size: 13))
                    Text("Controlled events and timing only. Never your text or API key.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06)))
    }
    private func refreshPermissions() { trusted = accessibility.trusted }
    private func shortcutRow(_ action: AssistantAction, _ shortcut: Shortcut, detail: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(action.title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutRecorder(label: shortcut.label) { new in status = onShortcut(action, new) ?? "Shortcut updated." }
                .frame(width: 215, height: 30)
        }
    }
}
