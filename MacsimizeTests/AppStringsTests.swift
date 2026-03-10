import XCTest
@testable import Macsimize

final class AppStringsTests: XCTestCase {
    override func tearDown() {
        AppStrings.resetPreferredLanguagesProvider()
        super.tearDown()
    }

    func testDefaultEnglishUsesMaximizeSpelling() {
        AppStrings.preferredLanguagesProvider = { ["en"] }

        XCTAssertEqual(AppStrings.maximizeModeTitle, "Maximize")
        XCTAssertEqual(AppStrings.maximizeAllMenuTitle, "Maximize All")
        XCTAssertEqual(AppStrings.behaviorSectionTitle, "Behavior")
        XCTAssertTrue(AppStrings.maximizeModeHelp.contains("pre-maximized"))
        XCTAssertTrue(AppStrings.fullScreenModeHelp.contains("full-screen behavior"))
    }

    func testBritishEnglishUsesMaximiseSpelling() {
        AppStrings.preferredLanguagesProvider = { ["en-GB"] }

        XCTAssertEqual(AppStrings.maximizeModeTitle, "Maximise")
        XCTAssertEqual(AppStrings.maximizeAllMenuTitle, "Maximise All")
        XCTAssertEqual(AppStrings.behaviorSectionTitle, "Behaviour")
        XCTAssertTrue(AppStrings.maximizeModeHelp.contains("pre-maximised"))
        XCTAssertTrue(AppStrings.fullScreenModeHelp.contains("full-screen behaviour"))
    }

    func testAustralianEnglishUsesMaximiseSpelling() {
        AppStrings.preferredLanguagesProvider = { ["en-AU"] }

        XCTAssertEqual(AppStrings.maximizeModeTitle, "Maximise")
        XCTAssertEqual(AppStrings.maximizeAllMenuTitle, "Maximise All")
        XCTAssertEqual(AppStrings.behaviorSectionTitle, "Behaviour")
    }
}
