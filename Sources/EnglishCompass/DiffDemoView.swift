import AppKit
import SwiftUI
import AssistantCore

/// Lab-only playground. Neither input is sent to a model or stored in defaults.
struct DiffDemoView: View {
    @State private var original = DiffDemoExample.examples[0].original
    @State private var proposed = DiffDemoExample.examples[0].proposed
    @State private var exampleIndex = 0
    @State private var granularity: TextDiff.Granularity = .words
    @State private var presentation: Presentation = .inline
    @State private var showWhitespace = false
    @State private var result: TextDiffResult?
    @State private var comparedOriginal = ""
    @State private var comparedProposed = ""
    @State private var comparedGranularity: TextDiff.Granularity = .words
    @State private var isComparing = false
    @State private var failure: String?
    @State private var comparisonTask: Task<Void, Never>?

    private enum Presentation: String, CaseIterable {
        case inline = "Inline", split = "Side by side", clean = "Final text"
    }

    private var isStale: Bool {
        result != nil && (Array(original.utf16) != Array(comparedOriginal.utf16)
            || Array(proposed.utf16) != Array(comparedProposed.utf16)
            || granularity != comparedGranularity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text Diff").font(.title2.weight(.semibold))
                    Text("Two plain texts. Local comparison. Rich-text highlights.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("LAB").font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            HStack {
                Picker("Example", selection: $exampleIndex) {
                    ForEach(DiffDemoExample.examples.indices, id: \.self) { index in
                        Text(DiffDemoExample.examples[index].title).tag(index)
                    }
                }.frame(maxWidth: 290)
                Button {
                    let example = DiffDemoExample.examples[exampleIndex]
                    original = example.original; proposed = example.proposed
                    compare()
                } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Load selected example").accessibilityLabel("Load selected example")
                Spacer()
                Picker("Compare by", selection: $granularity) {
                    Text("Words").tag(TextDiff.Granularity.words)
                    Text("Characters").tag(TextDiff.Granularity.characters)
                }.pickerStyle(.segmented).frame(width: 190)
                Button { compare() } label: { Image(systemName: "play.fill") }
                    .help("Compare texts").accessibilityLabel("Compare texts")
                    .accessibilityIdentifier("diff_compare")
                    .disabled(isComparing)
            }
            HStack(alignment: .top, spacing: 14) {
                input("Original", text: $original, identifier: "diff_original")
                input("Revised", text: $proposed, identifier: "diff_revised")
            }.frame(height: 175)
            HStack {
                Picker("View", selection: $presentation) {
                    ForEach(Presentation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 310)
                Spacer()
                Toggle("Show whitespace", isOn: $showWhitespace).toggleStyle(.checkbox)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(comparedProposed, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .help("Copy clean plain text").accessibilityLabel("Copy clean plain text")
                .disabled(result == nil || isStale || isComparing)
            }
            if let failure {
                Text(failure).font(.callout).foregroundStyle(.red)
            }
            HStack(spacing: 18) {
                Label("Added · underline", systemImage: "plus.circle.fill").foregroundStyle(.green)
                Label("Removed · strikethrough", systemImage: "minus.circle.fill").foregroundStyle(.red)
                Spacer()
                if isComparing {
                    ProgressView().controlSize(.small)
                    Text("Comparing…")
                } else if isStale {
                    Text("Inputs changed — press Compare.").foregroundStyle(.orange)
                } else if result?.isCoarse == true {
                    Text("Large change: whole-region comparison.").foregroundStyle(.secondary)
                } else if let result, result.parts.allSatisfy({ $0.kind == .unchanged }) {
                    Text("Identical texts").foregroundStyle(.secondary)
                }
            }.font(.caption)
            if let result {
                if presentation == .split {
                    HStack(spacing: 14) {
                        output(result.parts, keeping: .removed, identifier: "diff_output_original")
                        output(result.parts, keeping: .inserted, identifier: "diff_output_revised")
                    }
                } else {
                    output(result.parts, keeping: presentation == .clean ? .inserted : nil,
                           identifier: "diff_output")
                }
            } else {
                Text("Edit the texts and press Compare.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Literal text only; no Markdown interpretation or format diff. Whitespace markers are display-only. Limit: 16,000 Unicode scalars per input.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 740, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if result == nil { compare() } }
        .onDisappear { comparisonTask?.cancel() }
    }

    private func input(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.semibold))
            NativeTextEditor(text: text, placeholder: "Paste plain text…", identifier: identifier, label: title)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
        }.frame(maxWidth: .infinity)
    }

    private func output(_ parts: [DiffPart], keeping kind: DiffPart.Kind?, identifier: String) -> some View {
        DiffDemoRichText(text: DiffDemoFormatting.highlight(parts, keeping: kind, showWhitespace: showWhitespace,
                                                           marksChanges: presentation != .clean),
                         identifier: identifier)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compare() {
        guard !isComparing else { return }
        guard original.unicodeScalars.count <= 16_000, proposed.unicodeScalars.count <= 16_000 else {
            failure = "Please keep each input within 16,000 Unicode scalars. No text was truncated."
            return
        }
        let old = original, new = proposed, mode = granularity
        failure = nil
        isComparing = true
        comparisonTask = Task { @MainActor in
            let comparison = await Task.detached(priority: .userInitiated) {
                TextDiff.compare(original: old, proposed: new, granularity: mode)
            }.value
            isComparing = false
            guard !Task.isCancelled else { return }
            comparedOriginal = old; comparedProposed = new; comparedGranularity = mode
            result = comparison
        }
    }
}

enum DiffDemoFormatting {
    /// `keeping` filters deleted text from the revised view and inserted text
    /// from the original view. The inline view keeps every segment.
    static func highlight(_ parts: [DiffPart], keeping: DiffPart.Kind? = nil,
                          showWhitespace: Bool = false, marksChanges: Bool = true) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        for part in parts where keeping == nil || part.kind == .unchanged || part.kind == keeping {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.textColor
            ]
            switch marksChanges ? part.kind : .unchanged {
            case .unchanged: break
            case .inserted:
                attributes[.foregroundColor] = NSColor.systemGreen
                attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.13)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .removed:
                attributes[.foregroundColor] = NSColor.systemRed
                attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.10)
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            let text = showWhitespace ? visibleWhitespace(part.text) : part.text
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }

    private static func visibleWhitespace(_ text: String) -> String {
        text.map { character in
            switch character {
            case " ": return "·"
            case "\t": return "⇥"
            case "\r\n": return "↵\n"
            case "\n": return "↵\n"
            case "\r": return "↵\n"
            default: return String(character)
            }
        }.joined()
    }
}

private struct DiffDemoRichText: NSViewRepresentable {
    let text: NSAttributedString
    let identifier: String

    func makeNSView(context: Context) -> WrappingScrollView {
        let scroll = WrappingScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: WrappingScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel("Rich-text diff result")
        if let storage = view.textStorage, !storage.isEqual(to: text) {
            storage.setAttributedString(text)
        }
    }
}

private struct DiffDemoExample {
    let title: String
    let original: String
    let proposed: String

    static let examples: [DiffDemoExample] = [
        .init(title: "English correction", original: "She go to school every day.\n\nPlease helps me fix this bug.",
              proposed: "She goes to school every day.\n\nPlease help me resolve this issue."),
        .init(title: "Punctuation & whitespace", original: "Hello  world!\nFirst line.\n\nSecond\tline.",
              proposed: "Hello, world!\nFirst line.\nSecond line."),
        .init(title: "Chinese & emoji", original: "今天要修复这个问题。\nThe 👩🏽‍💻 fixed a bug.",
              proposed: "今天需要解决这个问题。\nThe 👩🏽‍💻 fixed the bug."),
        .init(title: "Repeated words", original: "The app is very very fast. It works on Mac.",
              proposed: "The app is very fast. It also works on Mac.")
    ]
}
