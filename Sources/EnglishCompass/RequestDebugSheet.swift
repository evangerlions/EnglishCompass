import SwiftUI
import AppKit

/// Displays the exact request body (never headers) and provider response for the
/// current inference. JSON bodies and raw SSE event payloads receive syntax
/// coloring; copying preserves the original captured response bytes.
struct RequestDebugSheet: View {
    let request: String?
    let response: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Request & Response").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Authorization headers and API keys are not included.")
                .font(.caption).foregroundStyle(.secondary)
            debugSection("Raw request", value: request, json: true)
            debugSection("Raw response", value: response, json: true)
        }
        .padding(20).frame(width: 680, height: 560)
    }

    private func debugSection(_ title: String, value: String?, json: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let value {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("Copy \(title.lowercased())")
                }
            }
            ScrollView([.vertical, .horizontal]) {
                Text(value.map { json ? JSONDebugView.highlight($0) : AttributedString($0) } ?? AttributedString("Not available"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            .frame(maxHeight: 210)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10)))
        }
    }
}
