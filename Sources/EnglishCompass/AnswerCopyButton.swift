import SwiftUI

/// Explicit colors keep the action readable when the window loses focus.
struct AnswerCopyButton: View {
    let index: Int
    let selected: Bool
    let copied: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(selected ? accent : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy")
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .accessibilityIdentifier("copy_answer_\(index)")
    }
}
