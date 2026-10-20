import AppKit
import SwiftUI

/// Uses one TextKit geometry for the caret, entered text and placeholder.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var fontSize: CGFloat = 15
    let identifier: String
    let label: String
    /// Reports (laid-out text content height, visible scroll height) whenever
    /// either changes, so the panel can fit itself to short or long input.
    var onMeasure: ((CGFloat, CGFloat) -> Void)?
    /// Opt-in chat behavior; other editors keep their normal multiline Return.
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WrappingScrollView {
        let scroll = WrappingScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
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
        // Fixed horizontal width with a tracking container is what makes text
        // wrap to the next line instead of scrolling horizontally.
        editor.textContainerInset = NSSize(width: 12, height: 10)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 100)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        scroll.documentView = editor
        context.coordinator.scroll = scroll
        configure(editor)
        editor.string = text
        return scroll
    }
    func updateNSView(_ scroll: WrappingScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scroll = scroll
        guard let editor = scroll.documentView as? PlaceholderTextView else { return }
        configure(editor)
        // Avoid resetting the selection, undo stack or an active IME composition.
        if editor.string != text && !editor.hasMarkedText() {
            editor.string = text
            editor.scrollRangeToVisible(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        editor.needsDisplay = true
        context.coordinator.report()
    }
    private func configure(_ editor: PlaceholderTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        if editor.font != font { editor.font = font }
        editor.placeholder = placeholder
        editor.onSubmit = onSubmit
        editor.setAccessibilityIdentifier(identifier)
        editor.setAccessibilityLabel(label)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        weak var scroll: NSScrollView?
        init(_ parent: NativeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? PlaceholderTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
            report()
        }
        /// Measures the laid-out text and the visible scroll area, deferred to
        /// after layout so width and wrapping are already settled.
        func report() {
            guard let editor = scroll?.documentView as? NSTextView else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let scroll = self.scroll,
                      let layout = editor.layoutManager, let container = editor.textContainer else { return }
                let used = layout.usedRect(for: container).height + editor.textContainerInset.height * 2
                let visible = scroll.contentView.bounds.height
                if used > 0, visible > 0 { self.parent.onMeasure?(used.rounded(), visible.rounded()) }
            }
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Let the input method consume Return while choosing/composing text.
        if let onSubmit, !hasMarkedText(),
           event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
            onSubmit()
            return
        }
        super.keyDown(with: event)
    }

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

/// Scroll view that keeps its document view exactly as wide as the visible
/// clip. This is the reliable way to make an NSTextView wrap: whenever the
/// clip width changes (window resize, SwiftUI layout), the text view and its
/// container are forced to that width, so long lines break instead of
/// extending the document horizontally.
///
/// Scrollers are forced to overlay style. A legacy scroller occupies layout
/// width, so when long text first shows it the clip narrows, wrapped text
/// reflows and changes height, the panel resizes, the scroller hides again —
/// an endless loop. Overlay scrollers float over the content and never change
/// its width, breaking that feedback cycle.
final class WrappingScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollerStyle = .overlay
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func tile() {
        super.tile()
        if scrollerStyle != .overlay { scrollerStyle = .overlay }
    }

    override func layout() {
        super.layout()
        guard let editor = documentView as? NSTextView else { return }
        let width = contentView.bounds.width
        guard width > 0 else { return }
        var frame = editor.frame
        if abs(frame.width - width) > 0.5 {
            frame.size.width = width
            editor.frame = frame
            editor.textContainer?.size = NSSize(width: max(0, width - editor.textContainerInset.width * 2),
                                                height: CGFloat.greatestFiniteMagnitude)
        }
    }
}
