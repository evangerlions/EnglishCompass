import AppKit
import SwiftUI
import AssistantCore

/// Content-sized reusable two-layer text. The outer result scroll view owns
/// scrolling and window-height limits; there is no per-answer nested scroller.
struct WritingDiffBody: View {
    let original: String
    let revised: String
    let navigation: (UInt16) -> Bool
    @State private var compared: Comparison?
    @State private var parts: [DiffPart]?

    private struct Comparison: Hashable {
        let original: String
        let revised: String
        static func == (lhs: Comparison, rhs: Comparison) -> Bool {
            lhs.original.utf16.elementsEqual(rhs.original.utf16)
                && lhs.revised.utf16.elementsEqual(rhs.revised.utf16)
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(Array(original.utf16))
            hasher.combine(Array(revised.utf16))
        }
    }
    private var comparison: Comparison { Comparison(original: original, revised: revised) }

    var body: some View {
        Group {
            if compared == comparison, let parts {
                WritingLayeredText(parts: parts, navigation: navigation)
            } else {
                Text(verbatim: revised).font(.system(size: 15))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: comparison) {
            let request = comparison
            let output = await Task.detached(priority: .userInitiated) {
                TextDiff.parts(original: request.original, proposed: request.revised)
            }.value
            guard !Task.isCancelled else { return }
            parts = output
            compared = request
        }
    }
}

struct WritingLayeredText: NSViewRepresentable {
    let parts: [DiffPart]
    let navigation: (UInt16) -> Bool

    func makeNSView(context: Context) -> DiffDemoLayeredDocument {
        let view = DiffDemoLayeredDocument()
        view.onNavigationKey = navigation
        view.setParts(parts, width: 480)
        return view
    }

    func updateNSView(_ view: DiffDemoLayeredDocument, context: Context) {
        view.onNavigationKey = navigation
        view.setParts(parts, width: max(100, view.bounds.width))
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DiffDemoLayeredDocument,
                      context: Context) -> CGSize? {
        let offeredWidth = proposal.width ?? 480
        let width = offeredWidth.isFinite ? max(100, offeredWidth) : 480
        nsView.setParts(parts, width: width)
        return CGSize(width: width, height: nsView.documentHeight)
    }
}
