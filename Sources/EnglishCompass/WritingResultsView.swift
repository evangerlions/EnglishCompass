import SwiftUI
import AssistantCore

/// Read-only answers keep emphasis separate from the exact text copied or replaced.
struct WritingResultsView: View {
    @ObservedObject var session: AssistantSession
    @FocusState private var keyboardFocused: Bool
    private let titles = ["通用", "口语", "学术"]
    private let accent = Color(red: 0.08, green: 0.43, blue: 0.40)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let result = session.result {
                        ForEach(result.candidates.indices, id: \.self) { index in
                            answer(result, index: index).id(index)
                        }
                        if !result.summary.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("整体说明").font(.system(size: 12, weight: .semibold))
                                Text(result.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.padding(.top, 2).accessibilityIdentifier("overall_explanation")
                        }
                    }
                    ForEach(session.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption)
                    }
                    if !session.message.isEmpty && session.message != "Copied." {
                        Text(session.message).font(.caption)
                    }
                    if session.hasCapturedTarget {
                        HStack {
                            Spacer()
                            Button("Replace selected answer") { session.replace() }
                                .disabled(!session.canReplace)
                        }
                    }
                }.padding(2)
            }
            .onChange(of: session.candidateIndex) { _, index in
                if let index { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .focusable().focusEffectDisabled().focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onKeyPress(.upArrow) { session.moveCandidate(-1); return .handled }
        .onKeyPress(.downArrow) { session.moveCandidate(1); return .handled }
        .onKeyPress(.return) { session.copy(); return .handled }
        Text("↑ ↓ 选择   ↵ 复制").font(.system(size: 10)).foregroundStyle(.tertiary)
    }

    private func answer(_ result: ModelResult, index: Int) -> some View {
        let selected = session.candidateIndex == index
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(result.candidates.count == 3 ? titles[index] : (result.candidates.count == 1 ? "回答" : "回答 \(index + 1)"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                Button {
                    session.chooseCandidate(index); session.copy(); keyboardFocused = true
                } label: {
                    Label(selected && session.message == "Copied." ? "Copied" : "Copy",
                          systemImage: selected && session.message == "Copied." ? "checkmark" : "doc.on.doc")
                }.controlSize(.small).accessibilityIdentifier("copy_answer_\(index)")
            }
            Text(emphasized(result.candidates[index], terms: result.highlights.indices.contains(index) ? result.highlights[index] : []))
                .font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
            if result.explanations.indices.contains(index) {
                Text(result.explanations[index]).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(selected ? accent.opacity(0.055) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? accent.opacity(0.5) : Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture { session.chooseCandidate(index); keyboardFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func emphasized(_ text: String, terms: [String]) -> AttributedString {
        var result = AttributedString(text)
        // Exact ranges only: no Markdown interpretation or mutation of the source answer.
        for term in terms where !term.isEmpty {
            var start = result.startIndex
            while start < result.endIndex, let range = result[start...].range(of: term) {
                result[range].font = .system(size: 15, weight: .semibold)
                start = range.upperBound
            }
        }
        return result
    }
}
