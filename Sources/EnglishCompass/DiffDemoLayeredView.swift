import AppKit
import SwiftUI
import AssistantCore

/// Native TextKit layout: only revised text occupies the reading baseline.
/// Removed text lives in independent, collision-free annotation lanes above it.
struct DiffDemoLayeredView: NSViewRepresentable {
    let parts: [DiffPart]

    func makeNSView(context: Context) -> DiffDemoLayeredScrollView {
        let scroll = DiffDemoLayeredScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.documentView = DiffDemoLayeredDocument()
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: DiffDemoLayeredScrollView, context: Context) {
        guard let document = scroll.documentView as? DiffDemoLayeredDocument else { return }
        document.setParts(parts, width: max(100, scroll.contentView.bounds.width))
    }
}

final class DiffDemoLayeredScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let document = documentView as? DiffDemoLayeredDocument else { return }
        document.reflow(width: contentView.bounds.width)
    }
}

final class DiffDemoLayeredDocument: NSView, NSUserInterfaceValidations {
    struct Annotation {
        let text: NSAttributedString
        let frame: NSRect
        let anchor: NSPoint
    }
    struct ReadingLine {
        let glyphs: NSRange
        let origin: NSPoint
        let frame: NSRect
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private(set) var selectedRange = NSRange(location: 0, length: 0)
    private var selectionAnchor = 0
    private var isSelecting = false
    private var boundaries: [Int] = [0]
    var onNavigationKey: ((UInt16) -> Bool)?
    var selectedText: String {
        (revisedText as NSString).substring(with: selectedRange)
    }
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private var parts: [DiffPart] = []
    private var layoutWidth: CGFloat = -1
    private(set) var annotations: [Annotation] = []
    private(set) var readingLines: [ReadingLine] = []
    private(set) var revisedText = ""
    private(set) var documentHeight: CGFloat = 0
    private let inset: CGFloat = 18

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier("diff_layered")
        setAccessibilityLabel("Full diff: revised sentences with removed text above")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setParts(_ newParts: [DiffPart], width: CGFloat) {
        if parts != newParts {
            parts = newParts
            selectedRange = NSRange(location: 0, length: 0)
            isSelecting = false
            layoutWidth = -1
        }
        reflow(width: width)
    }

    func reflow(width: CGFloat) {
        guard width > 0, abs(layoutWidth - width) > 0.5 else { return }
        layoutWidth = width
        let available = max(40, width - inset * 2)
        let rich = NSMutableAttributedString(attributedString: DiffDemoReview.text(parts, selectedID: nil))
        revisedText = rich.string
        boundaries = [0]
        var offset = 0
        for character in revisedText {
            offset += String(character).utf16.count
            boundaries.append(offset)
        }
        // Highlight changes without competing with old-text strikethrough.
        rich.removeAttribute(.underlineStyle, range: NSRange(location: 0, length: rich.length))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 0
        rich.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: rich.length))
        storage.setAttributedString(rich)
        container.size = NSSize(width: available, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)

        var rawLines: [(NSRange, NSRect)] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) {
            rect, _, _, glyphs, _ in rawLines.append((glyphs, rect))
        }
        // Pure deletion and terminal-newline changes need a visible anchor too.
        if rawLines.isEmpty {
            rawLines.append((NSRange(location: 0, length: 0), NSRect(x: 0, y: 0, width: available, height: 22)))
        } else if manager.extraLineFragmentTextContainer != nil {
            rawLines.append((NSRange(location: manager.numberOfGlyphs, length: 0), manager.extraLineFragmentRect))
        }

        var changesPerLine = Array(repeating: [(DiffDemoChange, CGFloat)](), count: rawLines.count)
        for change in DiffDemoChange.groups(parts) where !change.before.isEmpty {
            let location = min(change.proposedRange.location, storage.length)
            var lineIndex = rawLines.count - 1
            var x: CGFloat = 0
            if location < storage.length {
                let glyph = manager.glyphIndexForCharacter(at: location)
                if let found = rawLines.firstIndex(where: { NSLocationInRange(glyph, $0.0) }) {
                    lineIndex = found
                    let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                    x = rect.minX
                }
            } else if let last = rawLines.last, last.0.length > 0 {
                let used = manager.boundingRect(forGlyphRange: last.0, in: container)
                x = used.maxX
            }
            changesPerLine[lineIndex].append((change, x))
        }

        annotations = []
        readingLines = []
        var cursor = inset
        for (index, raw) in rawLines.enumerated() {
            var localNotes: [(NSAttributedString, NSRect, CGFloat)] = []
            var occupied: [NSRect] = []
            for (change, anchorX) in changesPerLine[index] {
                let text = oldText(change.before)
                let natural = ceil(text.size().width) + 2
                let noteWidth = min(available, max(24, natural))
                let left = min(max(0, anchorX), max(0, available - noteWidth))
                let height = max(17, ceil(text.boundingRect(
                    with: NSSize(width: noteWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
                var rect = NSRect(x: left, y: 0, width: noteWidth, height: height)
                // A long old phrase never shrinks, clips or overlaps another note.
                while let collision = occupied.first(where: { $0.insetBy(dx: -5, dy: -3).intersects(rect) }) {
                    rect.origin.y = collision.maxY + 5
                }
                occupied.append(rect)
                localNotes.append((text, rect, anchorX))
            }
            let noteHeight = occupied.map(\.maxY).max() ?? 0
            let baselineTop = cursor + (noteHeight > 0 ? noteHeight + 7 : 0)
            for (text, rect, anchorX) in localNotes {
                annotations.append(Annotation(text: text,
                    frame: rect.offsetBy(dx: inset, dy: cursor),
                    anchor: NSPoint(x: inset + min(anchorX, available), y: baselineTop - 2)))
            }
            let lineHeight = max(22, raw.1.height)
            readingLines.append(ReadingLine(glyphs: raw.0,
                origin: NSPoint(x: inset, y: baselineTop - raw.1.minY),
                frame: NSRect(x: inset, y: baselineTop, width: available, height: lineHeight)))
            cursor = baselineTop + lineHeight + 10
        }
        documentHeight = cursor + inset
        frame.size = NSSize(width: width, height: documentHeight)
        // Accessibility separates final text from annotations instead of reading
        // old and new words interleaved as one invalid sentence.
        setAccessibilityValue(revisedText)
        setAccessibilityHelp(annotations.map { "Removed: \($0.text.string)" }.joined(separator: "; "))
        needsDisplay = true
    }

    /// Selection offsets always refer to Revised, never annotation text.
    func select(from start: Int, to end: Int) {
        let lower = max(0, min(min(start, end), storage.length))
        let upper = max(lower, min(max(start, end), storage.length))
        let snappedStart = boundaries.last(where: { $0 <= lower }) ?? 0
        let snappedEnd = boundaries.first(where: { $0 >= upper }) ?? storage.length
        selectedRange = NSRange(location: snappedStart, length: snappedEnd - snappedStart)
        needsDisplay = true
    }

    /// Reverses the per-line translation used by draw(). Annotation lanes are
    /// ignored for an initial click, but dragging through them stays continuous.
    func textOffset(at point: NSPoint, dragging: Bool = false) -> Int? {
        guard !readingLines.isEmpty else { return nil }
        if !dragging, !readingLines.contains(where: { $0.frame.contains(point) }) { return nil }
        let line = readingLines.min {
            abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y)
        }!
        guard line.glyphs.length > 0 else { return storage.length }
        let local = NSPoint(x: point.x - line.origin.x, y: line.frame.midY - line.origin.y)
        var fraction: CGFloat = 0
        var glyph = manager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        glyph = min(max(glyph, line.glyphs.location), NSMaxRange(line.glyphs) - 1)
        let character = manager.characterIndexForGlyph(at: glyph)
        let start = boundaries.last(where: { $0 <= character }) ?? 0
        let end = boundaries.first(where: { $0 > character }) ?? storage.length
        return fraction > 0.5 ? end : start
    }

    private func wordRange(at offset: Int) -> NSRange {
        var found: NSRange?
        revisedText.enumerateSubstrings(in: revisedText.startIndex..<revisedText.endIndex,
                                        options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            let ns = NSRange(range, in: self.revisedText)
            if NSLocationInRange(offset, ns) { found = ns; stop = true }
        }
        return found ?? (revisedText as NSString).rangeOfComposedCharacterSequence(at: offset)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let offset = textOffset(at: point) else { return }
        if event.clickCount >= 3 {
            let range = (revisedText as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            select(from: range.location, to: NSMaxRange(range))
            isSelecting = false
        } else if event.clickCount == 2, offset < storage.length {
            let range = wordRange(at: offset)
            select(from: range.location, to: NSMaxRange(range))
            isSelecting = false
        } else {
            if !event.modifierFlags.contains(.shift) { selectionAnchor = offset }
            select(from: selectionAnchor, to: offset)
            isSelecting = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        autoscroll(with: event)
        if let offset = textOffset(at: convert(event.locationInWindow, from: nil), dragging: true) {
            select(from: selectionAnchor, to: offset)
        }
    }

    override func mouseUp(with event: NSEvent) { isSelecting = false }

    @objc func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedText, forType: .string)
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return selectedRange.length > 0 }
        if item.action == #selector(selectAll(_:)) { return storage.length > 0 }
        return false
    }

    override func selectAll(_ sender: Any?) {
        selectionAnchor = 0
        select(from: 0, to: storage.length)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .control]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": selectAll(nil); return
            case "c": copy(nil); return
            default: break
            }
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           onNavigationKey?(event.keyCode) == true { return }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private func oldText(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        // Invisible removed whitespace must remain inspectable in full diff.
        let visible = text.map { character -> String in
            switch character {
            case "\n", "\r", "\r\n": return "↵\n"
            case "\t": return "⇥"
            case " ": return "·"
            default: return String(character)
            }
        }.joined()
        return NSAttributedString(string: visible, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: paragraph
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let fullRange = NSRange(location: 0, length: storage.length)
        manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        if selectedRange.length > 0 {
            let active = window?.firstResponder === self && window?.isKeyWindow == true
            manager.addTemporaryAttributes([
                .backgroundColor: active ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor,
                .foregroundColor: active ? NSColor.selectedTextColor : NSColor.textColor
            ], forCharacterRange: selectedRange)
        }
        for line in readingLines where line.glyphs.length > 0 && line.frame.intersects(dirtyRect) {
            manager.drawBackground(forGlyphRange: line.glyphs, at: line.origin)
            manager.drawGlyphs(forGlyphRange: line.glyphs, at: line.origin)
        }
        for note in annotations where note.frame.union(NSRect(origin: note.anchor, size: NSSize(width: 1, height: 1))).intersects(dirtyRect) {
            note.text.draw(with: note.frame, options: [.usesLineFragmentOrigin, .usesFontLeading])
            let path = NSBezierPath()
            path.move(to: NSPoint(x: min(max(note.anchor.x, note.frame.minX), note.frame.maxX), y: note.frame.maxY + 1))
            path.line(to: note.anchor)
            NSColor.tertiaryLabelColor.setStroke()
            path.lineWidth = 0.7
            path.stroke()
            // Pure deletions have no highlighted new word. Mark their position.
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: note.anchor.x - 1.5, y: note.anchor.y, width: 3, height: 3)).fill()
        }
    }
}
