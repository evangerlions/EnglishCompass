import SwiftUI
import AssistantCore

struct ResultView: View {
    @ObservedObject var session: AssistantSession
    @State private var showDebug = false
    private let accent = Color(red: 0.08, green: 0.43, blue: 0.40)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(session.action.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if session.rawRequest != nil || session.rawResponse != nil {
                    Button { showDebug = true } label: { Image(systemName: "curlybraces") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Show raw request and response")
                        .accessibilityLabel("Show raw request and response")
                }
                Button { session.onSettings?() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Settings").accessibilityLabel("Settings")
            }
            if session.isUITest {
                Text("UI TEST FIXTURE - NOT REAL INFERENCE").font(.caption).foregroundStyle(.orange)
            }
            switch session.phase {
            case .input, .error:
                if session.phase == .error, !session.message.isEmpty { notice(session.message) }
                if session.phase == .error, let raw = session.rawResponse {
                    JSONDebugView(raw: raw)
                }
                editor($session.input, id: "manual_input", placeholder: "Paste or type your text...")
                HStack {
                    Button { session.pasteInput() } label: {
                        Label("Paste", systemImage: "clipboard")
                    }.controlSize(.large).accessibilityIdentifier("paste_button")
                    Spacer()
                    Button(session.action == .writeEnglish ? "Refine" : "Translate") { session.process() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("process_button")
                }
            case .processing:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(session.action == .writeEnglish ? "Refining..." : "Translating...")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("processing_state")
                HStack {
                    Spacer()
                    Button("Cancel") { session.cancel() }.controlSize(.large)
                }
            case .result:
                if session.action == .writeEnglish {
                    WritingResultsView(session: session)
                } else {
                    UnderstandingResultView(session: session)
                }
            case .replaced:
                Text("Draft replaced.").accessibilityIdentifier("replaced_state")
                Spacer()
            }
            footer
        }.padding(20).frame(width: 540).frame(maxHeight: .infinity, alignment: .top)
            .tint(accent)
            .sheet(isPresented: $showDebug) {
                RequestDebugSheet(request: session.rawRequest, response: session.rawResponse)
            }
            .onExitCommand { session.cancel() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(CloudAPIContract.model)
            if let seconds = session.elapsedSeconds {
                Text(String(format: "%.2f s", seconds)).monospacedDigit()
            } else if let started = session.requestStartedAt {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Text(String(format: "%.1f s", max(0, context.date.timeIntervalSince(started))))
                        .monospacedDigit()
                }
            }
            Spacer()
        }.font(.system(size: 10)).foregroundStyle(.secondary)
            .accessibilityIdentifier("request_metadata")
    }

    @ViewBuilder private var resultContent: some View {
        if let result = session.result, result.candidates.count > 1 {
            Text("Choose a meaning").font(.system(size: 12, weight: .medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.candidates.indices, id: \.self) { index in
                        Button { session.chooseCandidate(index) } label: {
                            HStack(alignment: .top) {
                                Text(result.candidates[index]).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                if session.candidateIndex == index { Image(systemName: "checkmark") }
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(accent.opacity(session.candidateIndex == index ? 0.10 : 0.03),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 120)
        }
        if session.candidateIndex != nil {
            editor($session.suggestion, id: "suggestion_editor")
                .onChange(of: session.suggestion) { _, _ in session.validateSuggestion() }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let result = session.result {
                        ForEach(result.explanations, id: \.self) { explanation in
                            Text(explanation).font(.system(size: 13)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(session.warnings, id: \.self) { notice($0) }
                    if !session.message.isEmpty { notice(session.message) }
                }
            }.frame(maxHeight: 100)
            HStack {
                Button("Copy") { session.copy() }.controlSize(.large).accessibilityIdentifier("copy_button")
                Spacer()
                if session.action == .writeEnglish, session.hasCapturedTarget {
                    Button("Replace") { session.replace() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(!session.canReplace).accessibilityIdentifier("replace_button")
                }
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    private func editor(_ text: Binding<String>, id: String, placeholder: String = "") -> some View {
        NativeTextEditor(text: text, placeholder: placeholder, identifier: id,
                         label: id == "manual_input" ? "Input text" : "Editable result")
            .frame(minHeight: 100, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "info.circle").font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
    }
}
