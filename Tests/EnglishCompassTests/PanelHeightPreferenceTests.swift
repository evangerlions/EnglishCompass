import XCTest
@testable import EnglishCompass

final class PanelHeightPreferenceTests: XCTestCase {
    @MainActor func testDefaultAndPersistence() throws {
        let name = "PanelHeightTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.maxPanelHeight, 1320)
        preferences.maxPanelHeight = 700
        XCTAssertEqual(Preferences(defaults: defaults).maxPanelHeight, 700)
    }

    @MainActor func testInvalidSavedHeightIsClamped() throws {
        let name = "PanelHeightTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for (saved, expected) in [(-1.0, 240.0), (9999, 2000)] {
            defaults.set(saved, forKey: "maxPanelHeight")
            XCTAssertEqual(Preferences(defaults: defaults).maxPanelHeight, expected)
        }
        XCTAssertEqual(Preferences.validPanelHeight(.nan), 1320)
    }

    func testCustomCapAndScreenLimitUseSameScrollbarThreshold() {
        XCTAssertEqual(PanelSizing.height(scrollContent: 2000, chrome: 120,
                                        screenHeight: 1200, maxHeight: 700), 700)
        XCTAssertTrue(PanelSizing.showsResultScrollIndicators(content: 2000, viewport: 580,
                        panelHeight: 700, screenHeight: 1200, maxHeight: 700))
        XCTAssertFalse(PanelSizing.showsResultScrollIndicators(content: 2000, viewport: 480,
                        panelHeight: 600, screenHeight: 1200, maxHeight: 700))
        XCTAssertEqual(PanelSizing.height(scrollContent: 2000, chrome: 120,
                                        screenHeight: 600, maxHeight: 700), 560)
        XCTAssertEqual(PanelSizing.height(scrollContent: 2000, chrome: 120, screenHeight: 1200,
                                        minHeight: PanelSizing.minQuestionHeight, maxHeight: 700), 700)
    }

    @MainActor func testGripDragDirectionAndBounds() {
        XCTAssertEqual(HeightGripView.height(start: 800, deltaY: -200, screenHeight: 1200), 600)
        XCTAssertEqual(HeightGripView.height(start: 600, deltaY: 200, screenHeight: 1200), 800)
        XCTAssertEqual(HeightGripView.height(start: 300, deltaY: -500, screenHeight: 1200), 240)
        XCTAssertEqual(HeightGripView.height(start: 800, deltaY: 1000, screenHeight: 1200), 1160)
    }
}
