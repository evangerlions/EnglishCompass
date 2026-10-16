import AppKit
import SwiftUI

/// Observe mouse-down inside just this card, without consuming the event. Native
/// text selection (including drag/long-press) and child buttons keep working.
struct CardSelectionObserver: NSViewRepresentable {
    var onSelect: () -> Void

    func makeNSView(context: Context) -> CardSelectionView {
        let view = CardSelectionView()
        view.onSelect = onSelect
        view.startObserving()
        return view
    }
    func updateNSView(_ view: CardSelectionView, context: Context) { view.onSelect = onSelect }
    static func dismantleNSView(_ view: CardSelectionView, coordinator: ()) { view.stopObserving() }
}

final class CardSelectionView: NSView {
    var onSelect: (() -> Void)?
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    func startObserving() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.observe(event)
            return event
        }
    }
    func observe(_ event: NSEvent) {
        guard event.type == .leftMouseDown, let window, event.window === window,
              !isHiddenOrHasHiddenAncestor,
              bounds.intersection(visibleRect).contains(convert(event.locationInWindow, from: nil)) else { return }
        onSelect?()
    }
    func stopObserving() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
