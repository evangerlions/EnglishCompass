import SwiftUI
import AssistantCore

/// Three answers are always shown together; ↑ ↓ moves the highlight between them.
/// Copy and replacement always use the exact plain-text answer, never the markup.
struct WritingResultsView: View {
    @ObservedObject var session: AssistantSession
    @FocusState private var keyboardFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    private let titles = ["通用", "口语", "学术"]
    private let accent = Color(red: 0.07, green: 0.56, blue: 0.50)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let result = session.result {
                            ForEach(result.candidates.indices, id: \.self) { index in
                                card(result, index: index).id(index)
                            }
                            if !result.summary.isEmpty { summary(result.summary) }
                        } else if session.isStreaming {
                            streamingCards
                        }
                        ForEach(session.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                        }
                        if !session.message.isEmpty && session.message != "Copied." {
                            Text(session.message).font(.caption)
                        }
                    }
                    // Room inside the scroll bounds so card shadows are not clipped;
                    // the negative outer padding keeps the visible card width unchanged.
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .onHeightChange { contentHeight = $0 }
                }
                .padding(.horizontal, -14)
                .scrollIndicators(.automatic)
                .onHeightChange { viewportHeight = $0 }
                .onChange(of: contentHeight == 0 || viewportHeight == 0 ? 0 : 1, initial: true) { _, _ in
                    session.reportResultMeasure(content: contentHeight, viewport: viewportHeight)
                }
                .onChange(of: session.candidateIndex) { _, index in
                    guard let index else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
            bottomBar
        }
        .focusable().focusEffectDisabled().focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onKeyPress(.upArrow) { withAnimation(.snappy(duration: 0.22)) { session.moveCandidate(-1) }; return .handled }
        .onKeyPress(.downArrow) { withAnimation(.snappy(duration: 0.22)) { session.moveCandidate(1) }; return .handled }
        .onKeyPress(.return) { session.copy(); return .handled }
        .onKeyPress(.space) { session.speakCurrent(); return .handled }
    }

    // MARK: Streaming

    /// Three cards are always present during streaming. The card currently being
    /// written shows its growing Markdown; cards not started yet show a light
    /// placeholder so the layout never jumps. Selection/copy are disabled until
    /// the finished payload passes strict parsing.
    @ViewBuilder
    private var streamingCards: some View {
        let live = session.liveWriteSections
        ForEach(0..<3, id: \.self) { index in
            streamingCard(index: index, markdown: live.cards[index])
        }
        if let notes = live.notes { streamingBlock(title: "讲解", markdown: notes) }
        if let summary = live.summary { streamingBlock(title: "整体说明", markdown: summary) }
    }

    private func streamingCard(index: Int, markdown: String?) -> some View {
        let active = markdown != nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(titles[index])
                    .font(.system(size: 11.5, weight: .bold)).tracking(0.6)
                    .foregroundStyle(active ? accent : Color.secondary)
                if active {
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(accent)
                        .symbolEffect(.variableColor.iterative)
                }
                Spacer()
            }
            if let markdown {
                Text(inlineMarkdown(markdown))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("等待生成…").font(.system(size: 13)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background { cardSurface(selected: active) }
    }

    private func streamingBlock(title: String, markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11.5, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
            Text(inlineMarkdown(markdown)).font(.system(size: 12.5)).foregroundStyle(.secondary)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Card

    private func card(_ result: ModelResult, index: Int) -> some View {
        let selected = session.candidateIndex == index
        let copied = selected && session.message == "Copied."
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label(for: result, index: index))
                    .font(.system(size: 11.5, weight: .bold)).tracking(0.6)
                    .foregroundStyle(selected ? accent : Color.secondary)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(accent)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                SpeakButton(speech: session.speech, text: result.candidates[index], tint: accent)
                    .accessibilityIdentifier("speak_answer_\(index)")
                copyButton(index: index, selected: selected, copied: copied)
            }
            answerText(result, index: index)
                .font(.system(size: 15))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.72))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background { cardSurface(selected: selected) }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { session.chooseCandidate(index) }
            keyboardFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Selected: near-solid glass pane, thin accent rim, inner top highlight and
    /// layered soft shadows. Unselected: light translucent pane with a hairline rim.
    /// Shadows sit on the fill only so strokes and text are not double-shadowed.
    private func cardSurface(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let dark = colorScheme == .dark
        let rim: CGFloat = selected ? 1 : 0.75
        return ZStack {
            shape
                .fill(Color(nsColor: .controlBackgroundColor).opacity(selected ? 0.94 : 0.30))
                .shadow(color: .black.opacity(selected ? (dark ? 0.35 : 0.09) : 0.03),
                        radius: selected ? 14 : 2, y: selected ? 6 : 1)
                .shadow(color: .black.opacity(selected ? (dark ? 0.25 : 0.06) : 0),
                        radius: 2, y: 1)
            if selected {
                shape.fill(accent.opacity(dark ? 0.12 : 0.06))
            }
            // Outer hairline defines the edge against the glass behind.
            shape.strokeBorder(selected ? accent.opacity(0.55)
                                        : Color.primary.opacity(dark ? 0.14 : 0.07),
                               lineWidth: rim)
            // Inner highlight: brighter along the top edge, fading downwards.
            shape.inset(by: rim)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.18 : (selected ? 0.9 : 0.6)),
                                                      Color.white.opacity(dark ? 0.02 : 0.08)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 1)
        }
    }

    @ViewBuilder
    private func copyButton(index: Int, selected: Bool, copied: Bool) -> some View {
        let button = Button {
            session.chooseCandidate(index); session.copy(); keyboardFocused = true
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
        }
        .help(copied ? "Copied" : "Copy")
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .accessibilityIdentifier("copy_answer_\(index)")
        if #available(macOS 26.0, *) {
            if selected { button.buttonStyle(.glassProminent).tint(accent) }
            else { button.buttonStyle(.glass) }
        } else {
            if selected { button.buttonStyle(.borderedProminent).tint(accent) }
            else { button.buttonStyle(.bordered) }
        }
    }

    // MARK: Summary and bottom bar

    private func summary(_ text: String) -> some View {
        bodyBlock(text, defaultTitle: "整体说明")
    }

    /// Renders the free-form explanatory Markdown (## Notes / ## Summary or any
    /// trailing prose). Headings are shown as small section titles; everything
    /// else is rendered as inline Markdown body text.
    private func bodyBlock(_ text: String, defaultTitle: String) -> some View {
        let sections = bodySections(text, defaultTitle: defaultTitle)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title)
                        .font(.system(size: 11.5, weight: .bold)).tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(inlineMarkdown(section.body))
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("overall_explanation")
    }

    private struct BodySection { let title: String; let body: String }

    private func bodySections(_ text: String, defaultTitle: String) -> [BodySection] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var sections: [BodySection] = []
        var title: String?
        var body: [String] = []
        func flush() {
            let trimmed = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sections.append(BodySection(title: title ?? defaultTitle, body: trimmed)) }
            body.removeAll(keepingCapacity: true)
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") {
                flush()
                title = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                body.append(line)
            }
        }
        flush()
        return sections
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            keycap("↑ ↓"); Text("选择")
            keycap("↵").padding(.leading, 6); Text("复制")
            keycap("Space").padding(.leading, 6); Text("朗读")
            Spacer()
            if session.hasCapturedTarget { replaceButton }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var replaceButton: some View {
        let button = Button("Replace selected answer") { session.replace() }
            .controlSize(.large)
            .disabled(!session.canReplace)
            .accessibilityIdentifier("replace_button")
        if #available(macOS 26.0, *) { button.buttonStyle(.glass) }
        else { button.buttonStyle(.bordered) }
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: Text

    /// Notes and summary are model Markdown; render inline emphasis instead of raw `**`.
    private func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
    }

    private func label(for result: ModelResult, index: Int) -> String {
        if result.candidates.count == 3 { return titles[index] }
        return result.candidates.count == 1 ? "回答" : "回答 \(index + 1)"
    }

    private func answerText(_ result: ModelResult, index: Int) -> Text {
        if result.markdownCandidates.indices.contains(index),
           let rich = try? AttributedString(markdown: result.markdownCandidates[index],
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(rich)
        }
        let terms = result.highlights.indices.contains(index) ? result.highlights[index] : []
        return Text(emphasized(result.candidates[index], terms: terms))
    }

    private func emphasized(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        // Exact ranges only: no Markdown interpretation or mutation of the source answer.
        for term in terms where !term.isEmpty {
            var start = result.startIndex
            while start < result.endIndex, let range = result[start...].range(of: term) {
                result[range].inlinePresentationIntent = .stronglyEmphasized
                start = range.upperBound
            }
        }
        return result
    }
}
