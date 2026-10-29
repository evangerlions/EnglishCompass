import AppKit

/// Presentation only: bringing back a window must not clear a draft, results,
/// streaming state, or the follow-up conversation.
@MainActor
enum AssistantWindowPresentation {
    static func configure(_ window: NSWindow) {
        window.hidesOnDeactivate = false
        if let panel = window as? NSPanel { panel.isFloatingPanel = false }
        window.level = .normal
    }

    /// Keep a Dock entry while a user window is open (including minimized windows).
    /// Closing the last window hides the entry without stopping background shortcuts.
    static func activationPolicy(for windows: [NSWindow], excluding closingWindow: NSWindow? = nil)
        -> NSApplication.ActivationPolicy {
        windows.contains { window in
            window !== closingWindow && (window.isVisible || window.isMiniaturized)
        } ? .regular : .accessory
    }

    static func updateDockVisibility(for windows: [NSWindow], excluding closingWindow: NSWindow? = nil) {
        let policy = activationPolicy(for: windows, excluding: closingWindow)
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    static func restore(_ window: NSWindow) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
