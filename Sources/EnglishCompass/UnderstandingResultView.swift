import SwiftUI
import AppKit
import AssistantCore

struct UnderstandingResultView: View {
    @ObservedObject var session: AssistantSession
    @FocusState private var keyboardFocused: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    private let accent = Color(red: 0.08, green: 0.43, blue: 0.40)

    var body: some View {
        VStack(spacing: 0) {
            if let result = session.result, let index = session.candidateIndex {
                resultBody(result: result, index: index)
            } else if session.isStreaming {
                streamingBody
            }
            // Copy is available whenever there is a finished or partial result.
            if session.result != nil || (session.isStreaming && !streamingCopyText.isEmpty) { bottomBar }
        }
        .focusable().focusEffectDisabled().focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onKeyPress(.space) { session.speakCurrent(); return .handled }
    }

    private var streamingCopyText: String {
        guard let t = session.liveUnderstandSections.translation else { return "" }
        return WritingMarkdownPayload.plainText(t)
    }

    private var bottomBar: some View {
        HStack {
            Button { copyCurrent() } label: {
                Label(session.message == "Copied." ? "Copied" : "Copy translation",
                      systemImage: session.message == "Copied." ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.large).accessibilityIdentifier("copy_button")
            Spacer()
            Text("Space 朗读原文").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func copyCurrent() {
        // During streaming copy the partial translation directly.
        if session.isStreaming, !streamingCopyText.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(streamingCopyText, forType: .string)
            session.message = "Copied."
            return
        }
        session.copy()
    }

    @ViewBuilder
    private var streamingBody: some View {
        let live = session.liveUnderstandSections
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    section(title: "原文", systemImage: "text.quote") {
                        HStack(alignment: .top, spacing: 8) {
                            Text(session.input).font(.system(size: 14))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                section(title: "翻译", systemImage: "character.bubble") {
                    if let t = live.translation {
                        Text(markdown(t)).font(.system(size: 17))
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 8) {
                            Text("等待生成…").font(.system(size: 14)).foregroundStyle(.tertiary)
                            Circle().fill(accent).frame(width: 6, height: 6).opacity(0.8)
                        }
                    }
                }
                if let notes = live.notes {
                    section(title: "讲解", systemImage: "text.book.closed") {
                        MarkdownBody(source: notes, fontSize: 13).foregroundStyle(.secondary)
                    }
                }
            }.padding(2)
                .onHeightChange { contentHeight = $0 }
        }
        .scrollIndicators(session.resultScrollIndicatorVisibility)
        .onHeightChange { viewportHeight = $0 }
        .onChange(of: contentHeight) { _, _ in
            if contentHeight > 0, viewportHeight > 0 {
                session.reportResultMeasure(content: contentHeight, viewport: viewportHeight)
            }
        }
        .onChange(of: viewportHeight) { _, _ in
            if contentHeight > 0, viewportHeight > 0 {
                session.reportResultMeasure(content: contentHeight, viewport: viewportHeight)
            }
        }
        .onAppear {
            if contentHeight > 0, viewportHeight > 0 {
                session.reportResultMeasure(content: contentHeight, viewport: viewportHeight)
            }
        }
    }

    @ViewBuilder
    private func resultBody(result: ModelResult, index: Int) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if result.candidates.count > 1 { meaningPicker(result) }
                    if !session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        section(title: "原文", systemImage: "text.quote") {
                            HStack(alignment: .top, spacing: 8) {
                                Text(session.input)
                                    .font(.system(size: 14))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                SpeakButton(speech: session.speech, text: session.input, tint: accent)
                                    .accessibilityIdentifier("speak_source")
                            }
                        }
                    }
                    section(title: "翻译", systemImage: "character.bubble") {
                        Text(translation(result, index: index))
                            .font(.system(size: 17, weight: .medium))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let notes = notesMarkdown(result)
                    if !notes.isEmpty {
                        section(title: "讲解", systemImage: "text.book.closed") {
                            MarkdownBody(source: notes, fontSize: 13).foregroundStyle(.secondary)
                        }
                    }
                    if !session.message.isEmpty && session.message != "Copied." {
                        Label(session.message, systemImage: "info.circle").font(.caption)
                    }
                }.padding(2)
                    .onHeightChange { contentHeight = $0 }
            }
            .scrollIndicators(session.resultScrollIndicatorVisibility)
            .onHeightChange { viewportHeight = $0 }
            .onChange(of: contentHeight) { _, _ in
                if contentHeight > 0, viewportHeight > 0 {
                    session.reportResultMeasure(content: contentHeight, viewport: viewportHeight)
                }
            }
            .onChange(of: viewportHeight) { _, _ in
                if contentHeight > 0, viewportHeight > 0 {
                    session.reportResultMeasure(content: contentHeight, viewport: viewportHeight)
                }
            }
    }

    private func meaningPicker(_ result: ModelResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选择含义").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(result.candidates.indices, id: \.self) { index in
                Button {
                    session.chooseCandidate(index)
                } label: {
                    HStack {
                        Text(result.candidates[index]).multilineTextAlignment(.leading)
                        Spacer()
                        if session.candidateIndex == index { Image(systemName: "checkmark") }
                    }.padding(8).background(accent.opacity(session.candidateIndex == index ? 0.10 : 0.03),
                                            in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }

    private func section<Content: View>(title: String, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func translation(_ result: ModelResult, index: Int) -> AttributedString {
        if result.markdownCandidates.indices.contains(index) {
            return markdown(result.markdownCandidates[index])
        }
        return AttributedString(result.candidates[index])
    }

    private func notesMarkdown(_ result: ModelResult) -> String {
        if !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return result.summary }
        return result.explanations.map { "- \($0)" }.joined(separator: "\n")
    }

    private func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full))) ?? AttributedString(source)
    }
}
