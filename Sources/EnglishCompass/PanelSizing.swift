import SwiftUI

/// Result panel sizing: grow with content, never past a maximum, then scroll.
enum PanelSizing {
    static let width: CGFloat = 540
    static let minResultHeight: CGFloat = 220
    static let maxResultHeight: CGFloat = 660
    /// Height used for input, processing and error states.
    static let defaultHeight: CGFloat = 470

    /// `overflow` is scroll content height minus visible scroll height: positive
    /// means content is hidden, negative means there is empty space to remove.
    /// Returns nil when the change is too small to be worth a resize.
    static func fittedHeight(current: CGFloat, overflow: CGFloat, screenHeight: CGFloat) -> CGFloat? {
        let maximum = max(minResultHeight, min(maxResultHeight, screenHeight - 40))
        let target = min(max(current + overflow, minResultHeight), maximum).rounded()
        return abs(target - current) > 1 ? target : nil
    }
}

extension View {
    /// Reports this view's laid-out height whenever it changes.
    func onHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { proxy in
            Color.clear
                .onAppear { action(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in action(height) }
        })
    }

    /// Measures a scroll view's content against its visible height and reports
    /// the difference to the session so the panel can fit its content.
    func reportsScrollOverflow(content: CGFloat, viewport: CGFloat, to session: AssistantSession) -> some View {
        onChange(of: content - viewport, initial: true) { _, overflow in
            guard content > 0, viewport > 0 else { return }
            session.resultOverflow = overflow
        }
    }
}
