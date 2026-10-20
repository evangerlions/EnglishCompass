import AppKit
import SwiftUI
import AssistantCore

struct QuestionSidebar: View {
    @ObservedObject var conversation: QuestionSession
    var onClose: () -> Void
    @State private var followsLatest = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Question", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { conversation.clearConversation() } label: { Image(systemName: "square.and.pencil") }
                    .help("New conversation").accessibilityLabel("New conversation")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .help("Close chat").accessibilityLabel("Close chat")
                    .accessibilityIdentifier("close_question")
            }.buttonStyle(.plain)
            Text("Current input and result included · \(conversation.model.rawValue)")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if conversation.messages.isEmpty {
                            Text("Ask about wording, grammar, or a follow-up question.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 20)
                        }
                        ForEach(conversation.messages) { message in
                            messageView(message)
                        }
                        Color.clear.frame(height: 1).id("question_bottom")
                            .onAppear { if followsLatest { proxy.scrollTo("question_bottom", anchor: .bottom) } }
                    }.padding(.vertical, 4)
                }
                .accessibilityIdentifier("question_messages")
                .onChange(of: conversation.messages) { _, _ in
                    if followsLatest { proxy.scrollTo("question_bottom", anchor: .bottom) }
                }
            }
            Toggle("Follow latest", isOn: $followsLatest)
                .font(.system(size: 11)).toggleStyle(.checkbox)
            if !conversation.error.isEmpty {
                Text(conversation.error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            NativeTextEditor(text: $conversation.draft, placeholder: "Ask a question…",
                             fontSize: 13, identifier: "question_input", label: "Question input",
                             onSubmit: { conversation.send() })
                .frame(height: 76)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            HStack {
                Text("Enter to send · Shift+Enter for a new line")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .help("Chat is not saved on this Mac.")
                Spacer()
                if conversation.isSending {
                    Button("Stop") { conversation.stop() }.accessibilityIdentifier("stop_question")
                } else {
                    Button("Send") { conversation.send() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("send_question")
                }
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.025))
    }

    private func messageView(_ message: QuestionMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if message.role == .assistant, !message.content.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).help("Copy reply").accessibilityLabel("Copy reply")
                }
            }
            if message.content.isEmpty {
                ProgressView().controlSize(.small)
            } else if message.role == .assistant {
                MarkdownBody(source: message.content, fontSize: 13)
            } else {
                Text(message.content).font(.system(size: 13)).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(message.role == .user ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
