import SwiftUI

/// Result panel sizing: grow with content, never past a maximum, then scroll.
enum PanelSizing {
    static let width: CGFloat = 540
    static let questionSidebarWidth: CGFloat = 360
    static let minQuestionHeight: CGFloat = 480

    static func questionUsesOverlay(screenWidth: CGFloat) -> Bool {
        screenWidth - 40 < width + questionSidebarWidth + 1
    }

    static func windowWidth(questionOpen: Bool, screenWidth: CGFloat) -> CGFloat {
        questionOpen && !questionUsesOverlay(screenWidth: screenWidth)
            ? width + questionSidebarWidth + 1 : width
    }
    static let minResultHeight: CGFloat = 220
    static let maxResultHeight: CGFloat = 660 * 2
    /// Input editor: compact when empty, grows with what is typed, then scrolls.
    static let minInputHeight: CGFloat = 240
    static let maxInputHeight: CGFloat = 560 * 2
    /// Height used for processing and replaced states (no measured content).
    static let defaultHeight: CGFloat = 360
    /// Ignore sub-pixel layout churn so a stable layout settles immediately.
    private static let tolerance: CGFloat = 4

    /// Desired panel height from measured scroll content and the fixed chrome
    /// measured at the current height (panel height minus the scroll viewport).
    /// Because chrome is measured, not guessed, resizing converges: the new
    /// viewport equals the content and the next target is the same height.
    static func height(scrollContent: CGFloat, chrome: CGFloat, screenHeight: CGFloat,
                       minHeight: CGFloat = minResultHeight, maxHeight: CGFloat = maxResultHeight) -> CGFloat {
        let maximum = max(minHeight, min(maxHeight, screenHeight - 40))
        return min(max(scrollContent + chrome, minHeight), maximum).rounded()
    }

    /// True only when the new height differs by more than layout tolerance.
    static func needsResize(from current: CGFloat, to target: CGFloat) -> Bool {
        abs(target - current) > tolerance
    }

    /// Overflow during a pending window growth is temporary, not scrollable UI.
    static func showsResultScrollIndicators(content: CGFloat, viewport: CGFloat,
                                            panelHeight: CGFloat, screenHeight: CGFloat,
                                            maxHeight: CGFloat = maxResultHeight) -> Bool {
        guard content > 0, viewport > 0 else { return false }
        let cap = max(minResultHeight, min(maxHeight, screenHeight - 40))
        return panelHeight >= cap - tolerance && content > viewport + tolerance
    }

    /// Fixed chrome at the current height. The scroll viewport is measured for
    /// that exact height, so their difference is the header/buttons/padding.
    static func chrome(panelHeight: CGFloat, viewport: CGFloat) -> CGFloat {
        max(0, panelHeight - viewport)
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
}
