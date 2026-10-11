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
    private var session: AssistantSession!
    private var item: NSStatusItem!
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var phaseObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = ApplicationMenus.make()
        session = AssistantSession(preferences: preferences, accessibility: accessibility, inference: inference)
        session.onClose = { [weak self] in self?.panel?.orderOut(nil) }
        session.onSettings = { [weak self] in self?.showSettings() }
        phaseObservation = session.$phase.sink { [weak self] phase in
            // Published emits before assignment; resize after SwiftUI receives the new phase.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session.phase == phase, let panel = self.panel else { return }
                let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
                let writingHeight = self.session.result?.candidates.count == 1 ? 300.0 : 500.0
                let height = min(phase == .result && self.session.action == .writeEnglish ? writingHeight : 470.0,
                                 bounds.height - 40)
                let top = panel.frame.maxY
                panel.setContentSize(NSSize(width: 540, height: height))
                panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: max(bounds.minY, top - panel.frame.height)))
            }
        }
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
        shortcuts.onAction = { [weak self] in self?.showAssistant($0) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "English Compass")
        let menu = NSMenu()
        add("Write in English", action: #selector(write), to: menu)
        add("Understand English", action: #selector(understand), to: menu)
        add("Manual input...", action: #selector(manual), to: menu)
        menu.addItem(.separator())
        add("Settings...", action: #selector(settings), to: menu)
        menu.addItem(.separator())
        add("Quit English Compass", action: #selector(quit), to: menu)
        item.menu = menu
        do { try shortcuts.register(write: preferences.writeShortcut, understand: preferences.understandShortcut) }
        catch { Diagnostics.event("shortcut_conflict") }
        Diagnostics.event("app_started")
        if ProcessInfo.processInfo.arguments.contains("--ui-test") { showAssistant(.writeEnglish, capture: false) }
        else { showSettings() }
    }
    func applicationWillTerminate(_ notification: Notification) { session.cancel(); inference.cancel() }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
    }
    @objc private func write() { showAssistant(.writeEnglish) }
    @objc private func understand() { showAssistant(.understandEnglish) }
    @objc private func manual() { showAssistant(.writeEnglish, capture: false) }
    @objc private func settings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showAssistant(_ action: AssistantAction, capture: Bool = true) {
        let anchor = session.begin(action, capture: capture)
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 470),
                                 styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "English Compass"
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isFloatingPanel = true; window.level = .floating; window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ResultView(session: session))
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel = window
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
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "English Compass Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, accessibility: accessibility,
                                                                     onShortcut: updateShortcut,
                                                                     onKeySaved: inference.useSavedCredential))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func updateShortcut(_ action: AssistantAction, _ shortcut: Shortcut) -> String? {
        let oldWrite = preferences.writeShortcut, oldUnderstand = preferences.understandShortcut
        let write = action == .writeEnglish ? shortcut : oldWrite
        let understand = action == .understandEnglish ? shortcut : oldUnderstand
        do {
            try shortcuts.register(write: write, understand: understand)
            preferences.writeShortcut = write; preferences.understandShortcut = understand
            return nil
        } catch {
            try? shortcuts.register(write: oldWrite, understand: oldUnderstand)
            return error.localizedDescription
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel { session.cancel(); return false }
        return true
    }
}
