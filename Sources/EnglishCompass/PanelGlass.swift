import AppKit
import Combine

/// Keeps the assistant panel height in sync with its result content.
/// Shared by the installed app and Lab mode so their sizing is identical.
///
/// The loop is: SwiftUI measures scroll content and viewport -> target height
/// is computed from both -> the window is resized at most once per measure.
/// Resizing never feeds the measurement directly; the view re-measures first,
/// and a height already within tolerance ends the loop, so it cannot oscillate.
@MainActor
final class PanelAutoFitter {
    private weak var panel: NSWindow?
    private let session: AssistantSession
    private var phaseObservation: AnyCancellable?
    private var measureObservation: AnyCancellable?
    private var inputMeasureObservation: AnyCancellable?
    private var questionObservation: AnyCancellable?
    private var heightPreferenceObservation: AnyCancellable?
    private var maximumHeight: CGFloat {
        max(CGFloat(Preferences.validPanelHeight(session.preferences.maxPanelHeight)),
            session.isQuestionOpen ? PanelSizing.minQuestionHeight : PanelSizing.minInputHeight)
    }
    private var currentHeight: CGFloat = 0
    /// Coalesces rapid measurements. A resize is applied only after the measured
    /// target has stayed unchanged for `settleDelay`, so intermediate layout
    /// passes (scroller appearing, one reflow pass) cannot oscillate the window.
    private var pendingTarget: CGFloat?
    private var settleWork: DispatchWorkItem?
    private let settleDelay: TimeInterval = 0.12
    private var isResizing = false

    init(panel: NSWindow, session: AssistantSession) {
        self.panel = panel
        self.session = session
        currentHeight = panel.contentRect(forFrameRect: panel.frame).height
        phaseObservation = session.$phase.sink { [weak self] phase in
            DispatchQueue.main.async {
                guard let self, self.session.phase == phase, phase != .result else { return }
                self.cancelSettle()
                self.session.showsResultScrollIndicators = false
                // Processing/error have no growing content; reset to the compact height.
                if phase != .input { self.resizePanel(to: PanelSizing.defaultHeight) }
            }
        }
        measureObservation = session.$resultMeasure
            .sink { [weak self] _ in DispatchQueue.main.async { self?.fitResult() } }
        inputMeasureObservation = session.$inputMeasure
            .sink { [weak self] _ in DispatchQueue.main.async { self?.fitInput() } }
        questionObservation = session.$isQuestionOpen
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateQuestionLayout() } }
        heightPreferenceObservation = session.preferences.$maxPanelHeight
            .dropFirst()
            .sink { [weak self] _ in
                let isDragging = self?.session.isAdjustingPanelHeight == true
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.cancelSettle()
                    if isDragging {
                        self.resizePanel(to: self.maximumHeight)
                    } else {
                        self.fitResult()
                        self.fitInput()
                    }
                }
            }
    }

    private func updateQuestionLayout() {
        guard let panel else { return }
        cancelSettle()
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        session.questionUsesOverlay = PanelSizing.questionUsesOverlay(screenWidth: bounds.width)
        resizePanel(to: session.isQuestionOpen ? max(currentHeight, PanelSizing.minQuestionHeight) : currentHeight)
        fitResult()
        fitInput()
    }

    private func fitResult() {
        guard session.phase == .result, !session.isAdjustingPanelHeight else { return }
        if let panel, let measure = session.resultMeasure {
            let screen = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
            let visible = PanelSizing.showsResultScrollIndicators(
                content: measure.content, viewport: measure.viewport,
                panelHeight: currentHeight, screenHeight: screen, maxHeight: maximumHeight)
            if visible != session.showsResultScrollIndicators {
                session.showsResultScrollIndicators = visible
            }
        } else {
            session.showsResultScrollIndicators = false
        }
        fit(session.resultMeasure, minHeight: PanelSizing.minResultHeight,
            maxHeight: maximumHeight)
    }

    private func fitInput() {
        guard !session.isAdjustingPanelHeight else { return }
        guard session.phase == .input || session.phase == .error else { return }
        fit(session.inputMeasure, minHeight: PanelSizing.minInputHeight,
            maxHeight: maximumHeight)
    }

    private func fit(_ measure: AssistantSession.ResultMeasure?, minHeight: CGFloat, maxHeight: CGFloat) {
        guard let panel, let measure, measure.content > 0, measure.viewport > 0, !isResizing else {
            cancelSettle()
            return
        }
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        // Chrome is measured at the current height, so after a settled resize
        // viewport == content and the target equals the current height.
        let chrome = PanelSizing.chrome(panelHeight: currentHeight, viewport: measure.viewport)
        let target = PanelSizing.height(scrollContent: measure.content, chrome: chrome, screenHeight: screen,
                                        minHeight: session.isQuestionOpen ? max(minHeight, PanelSizing.minQuestionHeight) : minHeight,
                                        maxHeight: maxHeight)
        guard PanelSizing.needsResize(from: currentHeight, to: target) else {
            cancelSettle()
            return
        }
        // Restart the settle timer whenever the target shifts; resize only when
        // measurements have been quiet for settleDelay.
        if target == pendingTarget { return }
        pendingTarget = target
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitPending() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    private func commitPending() {
        guard !isResizing, let target = pendingTarget else { return }
        pendingTarget = nil
        isResizing = true
        resizePanel(to: target)
        DispatchQueue.main.async { [weak self] in self?.isResizing = false }
    }

    private func cancelSettle() {
        settleWork?.cancel()
        settleWork = nil
        pendingTarget = nil
    }

    private func resizePanel(to height: CGFloat) {
        guard let panel else { return }
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        let clamped = min(height, maximumHeight, bounds.height - 40)
        let top = panel.frame.maxY
        let width = PanelSizing.windowWidth(questionOpen: session.isQuestionOpen, screenWidth: bounds.width)
        panel.setContentSize(NSSize(width: width, height: clamped))
        let x = max(bounds.minX, min(panel.frame.minX, bounds.maxX - panel.frame.width))
        panel.setFrameOrigin(NSPoint(x: x, y: max(bounds.minY, top - panel.frame.height)))
        currentHeight = clamped
    }
}

/// Liquid Glass background for the assistant panel on macOS 26+, translucent
/// material before that. Both the installed app and Lab mode use this.
enum PanelGlass {
    static func make(content: NSView) -> NSView {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }
}
