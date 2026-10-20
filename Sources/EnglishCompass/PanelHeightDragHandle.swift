import AppKit
import SwiftUI

/// A bottom-edge grip: resize in place, while retaining automatic content sizing
/// for future results. No separate settings control is needed.
struct PanelHeightDragHandle: NSViewRepresentable {
    let session: AssistantSession

    func makeNSView(context: Context) -> HeightGripView {
        let view = HeightGripView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: HeightGripView, context: Context) {
        view.onStart = { session.isAdjustingPanelHeight = true }
        view.onHeight = { session.preferences.maxPanelHeight = Double($0) }
        view.onEnd = { session.isAdjustingPanelHeight = false }
    }
}

final class HeightGripView: NSView {
    var onStart: (() -> Void)?
    var onHeight: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var dragOrigin: (y: CGFloat, height: CGFloat)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag up or down to adjust the maximum height"
        setAccessibilityLabel("Adjust maximum window height")
        setAccessibilityIdentifier("panel_height_grip")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 20, y: bounds.midY - 2,
                                       width: 40, height: 4), xRadius: 2, yRadius: 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragOrigin = (NSEvent.mouseLocation.y, window.contentRect(forFrameRect: window.frame).height)
        onStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let window else { return }
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        onHeight?(Self.height(start: origin.height, deltaY: origin.y - NSEvent.mouseLocation.y,
                              screenHeight: screenHeight))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        // Commit the final position even if the drag ended between resize updates.
        mouseDragged(with: event)
        dragOrigin = nil
        onEnd?()
    }

    static func height(start: CGFloat, deltaY: CGFloat, screenHeight: CGFloat) -> CGFloat {
        min(CGFloat(Preferences.validPanelHeight(Double(start + deltaY))), max(240, screenHeight - 40))
    }
}
