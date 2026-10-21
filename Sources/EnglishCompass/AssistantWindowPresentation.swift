import AppKit

/// Presentation only: bringing back a window must not clear a draft, results,
/// streaming state, or the follow-up conversation.
@MainActor
enum AssistantWindowPresentation {
    static func configure(_ window: NSWindow) {
        window.hidesOnDeactivate = false
    }

    static func restore(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
