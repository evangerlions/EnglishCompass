import XCTest
@testable import EnglishCompass

final class PanelSizingTests: XCTestCase {
    func testShortContentShrinksButNotBelowMinimum() {
        XCTAssertEqual(PanelSizing.fittedHeight(current: 470, overflow: -150, screenHeight: 1000), 320)
        XCTAssertEqual(PanelSizing.fittedHeight(current: 470, overflow: -400, screenHeight: 1000), PanelSizing.minResultHeight)
    }
    func testLongContentGrowsUpToMaximumThenScrolls() {
        XCTAssertEqual(PanelSizing.fittedHeight(current: 470, overflow: 100, screenHeight: 1000), 570)
        XCTAssertEqual(PanelSizing.fittedHeight(current: 470, overflow: 900, screenHeight: 1000), PanelSizing.maxResultHeight)
    }
    func testMaximumNeverExceedsScreenAndTinyChangesAreIgnored() {
        XCTAssertEqual(PanelSizing.fittedHeight(current: 470, overflow: 900, screenHeight: 600), 560)
        XCTAssertNil(PanelSizing.fittedHeight(current: 470, overflow: 0.5, screenHeight: 1000))
        XCTAssertNil(PanelSizing.fittedHeight(current: PanelSizing.maxResultHeight, overflow: 300, screenHeight: 1000))
    }
}
