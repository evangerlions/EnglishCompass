import AppKit
import SwiftUI
import AssistantCore

/// Local-only test mode, started with `swift run EnglishCompass --lab`.
///
/// The main surface is the production ResultView in the same glass panel and
/// with the same adaptive sizing; Lab only adds a badge, a minimal menu and an
/// inspector sheet. There are no hot keys, status item, Accessibility capture
/// or Keychain reads: the key comes from BAILIAN_API_KEY and settings use a
/// separate defaults suite.
@MainActor
final class LabAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let defaultsSuite = "com.zook.EnglishCompass.lab"
    static let keyVariable = "BAILIAN_API_KEY"

    private var panel: NSWindow?
    private var fitter: PanelAutoFitter?
    private var session: AssistantSession!
    private var preferences: Preferences!
    private var keyAvailable = false
    private var inspectorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMenu()
        let defaults = UserDefaults(suiteName: Self.defaultsSuite) ?? .standard
        preferences = Preferences(defaults: defaults)
        let key = Self.environmentKey()
        keyAvailable = key != nil
        let inference = InferenceService(credential: {
            guard let key else { throw AssistantFailure.cloudKeyMissing }
            return key
        })
        session = AssistantSession(preferences: preferences, accessibility: AccessibilityBridge(),
                                   inference: inference)
        session.onClose = {}
        session.onSettings = {}
        session.begin(.writeEnglish, capture: false)

        let root = ResultView(session: session, modeBadge: "LAB", showsSettingsButton: false) { [weak self] in
            self?.showInspector()
        }
        // Lab is a normal window, not an NSPanel: panels created while launching
        // from Terminal can end up invisible on the active space.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PanelSizing.width, height: PanelSizing.minInputHeight),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        AssistantWindowPresentation.configure(window)
        window.title = "English Compass Lab"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.delegate = self
        window.contentView = PanelGlass.make(content: NSHostingView(rootView: root))
        // Place it explicitly on the main visible screen instead of centering.
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                      y: frame.midY - size.height / 2))
        fitter = PanelAutoFitter(panel: window, session: session)
        panel = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        print(key == nil
              ? "event=lab_started key=missing hint=export \(Self.keyVariable) in ~/.zshrc and relaunch from a new Terminal"
              : "event=lab_started key=environment")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel { AssistantWindowPresentation.restore(panel) }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the inspector alone must not quit; only the panel close counts.
        if NSApp.windows.contains(where: { $0 === panel }) { return false }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { session?.cancel() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { NSApp.terminate(nil); return false }
        return true
    }

    // MARK: Menu (Lab has no status item)

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit English Compass Lab", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = submenu
        menu.addItem(appItem)

        let file = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item(title: "Write / Translate", key: "1", action: #selector(chooseWrite)))
        fileMenu.addItem(item(title: "Understand English", key: "2", action: #selector(chooseUnderstand)))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(title: "Run", key: "\r", action: #selector(run)))
        file.submenu = fileMenu
        menu.addItem(file)

        let editItem = NSMenuItem()
        editItem.submenu = ApplicationMenus.editMenu()
        menu.addItem(editItem)

        let debug = NSMenuItem()
        let debugMenu = NSMenu(title: "Debug")
        debugMenu.addItem(item(title: "Inspector", key: "i", modifiers: [.command, .option], action: #selector(showInspector)))
        debug.submenu = debugMenu
        menu.addItem(debug)
        return menu
    }

    private func item(title: String, key: String, modifiers: NSEvent.ModifierFlags = [.command],
                      action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func chooseWrite() { begin(.writeEnglish) }
    @objc private func chooseUnderstand() { begin(.understandEnglish) }
    @objc private func run() { session.process() }

    private func begin(_ action: AssistantAction) {
        session.begin(action, capture: false)
    }

    // MARK: Inspector

    @objc private func showInspector() {
        if inspectorWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Lab Inspector"
            window.minSize = NSSize(width: 480, height: 360)
            window.contentView = NSHostingView(rootView: LabInspector(session: session, preferences: preferences))
            window.center()
            inspectorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        inspectorWindow?.makeKeyAndOrderFront(nil)
    }

    static func environmentKey(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let raw = environment[keyVariable] else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), key.utf8.count <= 4096 else { return nil }
        return key
    }
}

/// Prompt and raw request/response inspector, in a separate window so the main
/// panel stays visually identical to the installed app.
private struct LabInspector: View {
    @ObservedObject var session: AssistantSession
    @ObservedObject var preferences: Preferences
    @State private var tab: Tab = .response

    enum Tab: String, CaseIterable { case response = "Raw response", request = "Raw request", prompt = "System prompt" }

    var body: some View {
        VStack(spacing: 0) {
            ModelSettingsView(preferences: preferences).padding(12)
            WritingLanguageSettingsView(preferences: preferences).padding(.horizontal, 12).padding(.bottom, 12)
            Divider()
            HStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 400)
                Spacer()
                if tab == .prompt {
                    Text("Additional instructions (Lab only)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                .disabled(text.isEmpty)
            }.padding(12)
            if tab == .prompt {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: session.action == .writeEnglish
                              ? $preferences.writeInstructions
                              : $preferences.understandInstructions)
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                }.padding(.horizontal, 12)
                Divider()
            }
            ScrollView {
                Text(text.isEmpty ? AttributedString("Nothing yet. Run a request in the panel.")
                     : tab == .prompt ? AttributedString(text) : JSONDebugView.highlight(text))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    private var text: String {
        switch tab {
        case .response: session.rawResponse ?? ""
        case .request: session.rawRequest ?? ""
        case .prompt:
            (try? CloudAPIContract.prompt(action: session.action,
                                          additionalInstructions: preferences.instructions(for: session.action),
                                          targetLanguage: preferences.writingLanguage)) ?? ""
        }
    }

}
