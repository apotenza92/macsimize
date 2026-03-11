import XCTest
@testable import Macsimize

final class AppStringsTests: XCTestCase {
    override func tearDown() {
        AppStrings.resetPreferredLanguagesProvider()
        AppStrings.resetCurrentVersionProvider()
        super.tearDown()
    }

    func testDefaultEnglishUsesMaximizeSpelling() {
        AppStrings.preferredLanguagesProvider = { ["en"] }

        XCTAssertEqual(AppStrings.maximizeModeTitle, "Maximize")
        XCTAssertEqual(AppStrings.maximizeAllMenuTitle, "Maximize All")
        XCTAssertEqual(AppStrings.behaviorSectionTitle, "Behavior")
        XCTAssertEqual(
            AppStrings.maximizeModeHelp,
            [
                "Click again to restore the pre-maximized size.",
                "⌥ Option-click does Full Screen instead."
            ].joined(separator: "\n")
        )
        XCTAssertEqual(
            AppStrings.fullScreenModeHelp,
            [
                "Native macOS behavior.",
                "⌥ Option-click does Maximize instead."
            ].joined(separator: "\n")
        )
    }

    func testBritishEnglishUsesMaximiseSpelling() {
        AppStrings.preferredLanguagesProvider = { ["en-GB"] }

        XCTAssertEqual(AppStrings.maximizeModeTitle, "Maximise")
        XCTAssertEqual(AppStrings.maximizeAllMenuTitle, "Maximise All")
        XCTAssertEqual(AppStrings.behaviorSectionTitle, "Behaviour")
        XCTAssertEqual(
            AppStrings.maximizeModeHelp,
            [
                "Click again to restore the pre-maximised size.",
                "⌥ Option-click does Full Screen instead."
            ].joined(separator: "\n")
        )
        XCTAssertEqual(
            AppStrings.fullScreenModeHelp,
            [
                "Native macOS behavior.",
                "⌥ Option-click does Maximise instead."
            ].joined(separator: "\n")
        )
    }

    func testAustralianEnglishUsesMaximiseSpelling() {
        AppStrings.preferredLanguagesProvider = { ["en-AU"] }

        XCTAssertEqual(AppStrings.maximizeModeTitle, "Maximise")
        XCTAssertEqual(AppStrings.maximizeAllMenuTitle, "Maximise All")
        XCTAssertEqual(AppStrings.behaviorSectionTitle, "Behaviour")
    }

    func testCurrentVersionStatusMessageUsesProvidedVersion() {
        AppStrings.currentVersionProvider = { "2.4.6" }

        XCTAssertEqual(AppStrings.currentVersionStatusMessage, "Current version: 2.4.6")
    }
}
