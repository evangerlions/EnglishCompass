import AppKit
import SwiftUI

/// Uses one TextKit geometry for the caret, entered text and placeholder.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var fontSize: CGFloat = 15
    let identifier: String
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let editor = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 12, height: 10)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 100)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        scroll.documentView = editor
        configure(editor)
        editor.string = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PlaceholderTextView else { return }
        configure(editor)
        // Avoid resetting the selection, undo stack or an active IME composition.
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
        editor.needsDisplay = true
    }
    private func configure(_ editor: PlaceholderTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        if editor.font != font { editor.font = font }
        editor.placeholder = placeholder
        editor.setAccessibilityIdentifier(identifier)
        editor.setAccessibilityLabel(label)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        init(_ parent: NativeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? PlaceholderTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        withPlaceholderLayout { layout in
            layout.drawGlyphs(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs),
                              at: textContainerOrigin)
        }
    }
    // Exposed internally for geometry regression tests, not a separate UI offset.
    var placeholderFirstGlyphOrigin: NSPoint {
        withPlaceholderLayout { layout in
            let line = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let glyph = layout.location(forGlyphAt: 0)
            return NSPoint(x: textContainerOrigin.x + line.minX + glyph.x,
                           y: textContainerOrigin.y + line.minY + glyph.y)
        }
    }
    private func withPlaceholderLayout<T>(_ body: (NSLayoutManager) -> T) -> T {
        let storage = NSTextStorage(string: placeholder, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default
        ])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: textContainer?.size ?? bounds.size)
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return body(layout)
    }
}
