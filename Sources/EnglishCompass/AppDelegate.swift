import AppKit
import SwiftUI
import Combine
import AssistantCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = Preferences()
    private let accessibility = AccessibilityBridge()
    private let inference = InferenceService()
    private let shortcuts = GlobalShortcuts()
    private lazy var speech = SpeechService(preferences: preferences)
    private var session: AssistantSession!
    private var item: NSStatusItem!
    private var panel: NSWindow?
    private var settingsWindow: NSWindow?
    private var readAloudTask: Task<Void, Never>?
    private var fitter: PanelAutoFitter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = ApplicationMenus.make()
        session = AssistantSession(preferences: preferences, accessibility: accessibility, inference: inference,
                                   speech: speech)
        session.onClose = { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.updateDockVisibility()
        }
        session.onSettings = { [weak self] in self?.showSettings() }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--cloud-smoke-test") {
            Task {
                let passed = await CloudSmokeTest.run(inference)
                print(passed ? "event=cloud_smoke_passed" : "event=cloud_smoke_failed")
                exit(passed ? 0 : 1)
            }
            return
        }
        if arguments.contains("--ui-test"), arguments.contains("--self-test") {
            Task {
                let passed = await SessionSmokeTest.run(session)
                print(passed ? "event=session_smoke_passed" : "event=session_smoke_failed")
                NSApp.terminate(nil)
            }
            return
        }
        if arguments.contains("--ui-test"), let index = arguments.firstIndex(of: "--preview-dir"), arguments.indices.contains(index + 1) {
            do {
                try PreviewRenderer.render(to: URL(fileURLWithPath: arguments[index + 1]), session: session,
                                           preferences: preferences, accessibility: accessibility, inference: inference)
                print("event=fixture_previews_saved")
            } catch { print("event=fixture_preview_failed") }
            NSApp.terminate(nil)
            return
        }
        shortcuts.onShortcut = { [weak self] kind in
            guard let self else { return }
            if let action = kind.action { self.showAssistant(action) } else { self.readAloud() }
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "English Compass")
        let menu = NSMenu()
        add("Write / Translate", action: #selector(write), to: menu)
        add("Understand English", action: #selector(understand), to: menu)
        add("Read Selection Aloud", action: #selector(readAloudMenu), to: menu)
        add("Manual input...", action: #selector(manual), to: menu)
        menu.addItem(.separator())
        add("Settings...", action: #selector(settings), to: menu)
        menu.addItem(.separator())
        add("Quit English Compass", action: #selector(quit), to: menu)
        item.menu = menu
        do { try shortcuts.register(preferences.allShortcuts) }
        catch { Diagnostics.event("shortcut_conflict") }
        Diagnostics.event("app_started")
        if ProcessInfo.processInfo.arguments.contains("--ui-test") { showAssistant(.writeEnglish, capture: false) }
        else { showSettings() }
    }
    /// Dock clicks restore the same panel, not a new capture or model request.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel {
            AssistantWindowPresentation.restore(panel)
        } else {
            showAssistant(.writeEnglish, capture: false)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { session.cancel(); inference.cancel() }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
    }
    @objc private func write() { showAssistant(.writeEnglish) }
    @objc private func understand() { showAssistant(.understandEnglish) }
    @objc private func manual() { showAssistant(.writeEnglish, capture: false) }
    @objc private func readAloudMenu() { readAloud() }
    @objc private func settings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Global Read Aloud: speaks the current selection without opening the panel.
    /// Pressing it again while speaking stops playback.
    private func readAloud() {
        if speech.isSpeaking { speech.stop(); return }
        // While the assistant panel is frontmost, read what it shows instead.
        if panel?.isKeyWindow == true, session.speechText != nil { session.speakCurrent(); return }
        readAloudTask?.cancel()
        readAloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.accessibility.readSelection()
                guard !Task.isCancelled else { return }
                self.speech.speak(text)
            } catch {
                Diagnostics.event("speech_no_selection")
                if (error as? AssistantFailure) == .permission { self.showSettings() } else { NSSound.beep() }
            }
        }
    }

    private func showAssistant(_ action: AssistantAction, capture: Bool = true) {
        session.begin(action, capture: capture) { [weak self] anchor in
            guard let self else { return }
            // Resolve any Keychain prompt before the panel exists on screen.
            if !self.session.isUITest { self.inference.prepareCredential() }
            self.presentAssistant(anchor: anchor)
        }
    }

    private func presentAssistant(anchor: CGRect?) {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 470),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "English Compass"
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            AssistantWindowPresentation.configure(window)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = PanelGlass.make(content: NSHostingView(rootView: ResultView(session: session)))
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel = window
            fitter = PanelAutoFitter(panel: window, session: session)
        }
        let screen = NSScreen.screens.first { screen in
            guard let anchor else { return screen == NSScreen.main }
            return screen.frame.contains(CGPoint(x: anchor.midX, y: screen.frame.maxY - anchor.midY))
        } ?? NSScreen.main
        if let screen {
            let bounds = screen.visibleFrame
            let x = anchor.map { $0.midX - 270 } ?? bounds.midX - 270
            let y = anchor.map { screen.frame.maxY - $0.minY - 470 } ?? bounds.midY - 170
            panel?.setFrameOrigin(CGPoint(x: min(max(x, bounds.minX), bounds.maxX - 540),
                                          y: min(max(y, bounds.minY), bounds.maxY - 470)))
        }
        if let panel { AssistantWindowPresentation.restore(panel) }
    }
    /// Resizes the panel keeping its top edge fixed, clamped to the visible screen.
    private func resizePanel(to height: CGFloat) {
        guard let panel else { return }
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let clamped = min(height, bounds.height - 40)
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: PanelSizing.width, height: clamped))
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: max(bounds.minY, top - panel.frame.height)))
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "English Compass Settings"; window.isReleasedWhenClosed = false
            window.delegate = self
            AssistantWindowPresentation.configure(window)
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, accessibility: accessibility,
                                                                     onShortcut: updateShortcut,
                                                                     onKeySaved: inference.useSavedCredential,
                                                                     onOpenAction: { [weak self] action in
                                                                         self?.showAssistant(action, capture: false)
                                                                     },
                                                                     speech: speech))
            window.center(); settingsWindow = window
        }
        if let settingsWindow { AssistantWindowPresentation.restore(settingsWindow) }
    }
    private func updateShortcut(_ kind: ShortcutKind, _ shortcut: Shortcut) -> String? {
        let old = preferences.allShortcuts
        var updated = old
        updated[kind] = shortcut
        do {
            try shortcuts.register(updated)
            preferences.setShortcuts(updated)
            return nil
        } catch {
            try? shortcuts.register(old)
            return error.localizedDescription
        }
    }
    private func updateDockVisibility(excluding closingWindow: NSWindow? = nil) {
        AssistantWindowPresentation.updateDockVisibility(
            for: [panel, settingsWindow].compactMap { $0 }, excluding: closingWindow)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        updateDockVisibility(excluding: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Only the explicit Quit command stops the status item and global shortcuts.
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { session.cancel(); return false }
        return true
    }
}
