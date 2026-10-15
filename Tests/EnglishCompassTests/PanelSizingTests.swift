import XCTest
@testable import EnglishCompass

final class PanelSizingTests: XCTestCase {
    /// Simulates the live fit loop at the current height until it settles.
    private func settle(content: CGFloat, start: CGFloat, screen: CGFloat = 1000) -> [CGFloat] {
        var height = start
        var steps: [CGFloat] = []
        // Viewport = panel height minus fixed chrome of 110, as in the real layout.
        let fixedChrome: CGFloat = 110
        for _ in 0..<10 {
            let viewport = max(0, height - fixedChrome)
            let chrome = PanelSizing.chrome(panelHeight: height, viewport: viewport)
            let target = PanelSizing.height(scrollContent: content, chrome: chrome, screenHeight: screen)
            guard PanelSizing.needsResize(from: height, to: target) else { break }
            height = target
            steps.append(height)
        }
        return steps
    }

    func testGrowingLoopSettlesWithoutOscillation() {
        // Content needs 460 in the scroll area; chrome is 110 -> target 570 once.
        XCTAssertEqual(settle(content: 460, start: 470), [570])
    }

    func testShrinkingLoopSettlesInOneStep() {
        // Short content: target collapses to the minimum in a single move.
        XCTAssertEqual(settle(content: 90, start: 600), [PanelSizing.minResultHeight])
    }

    func testContentOverMaximumSettlesAtMaximumAndStopsResizing() {
        XCTAssertEqual(settle(content: 2000, start: 470), [PanelSizing.maxResultHeight])
    }

    func testScreenLimitIsRespected() {
        let steps = settle(content: 2000, start: 470, screen: 600)
        XCTAssertEqual(steps, [560])
    }

    func testSubPixelDifferenceDoesNotResize() {
        XCTAssertFalse(PanelSizing.needsResize(from: 470, to: 472))
        XCTAssertTrue(PanelSizing.needsResize(from: 470, to: 475))
    }

    func testChromeIsTheDifferenceBetweenPanelAndViewport() {
        XCTAssertEqual(PanelSizing.chrome(panelHeight: 470, viewport: 360), 110)
    }
}
