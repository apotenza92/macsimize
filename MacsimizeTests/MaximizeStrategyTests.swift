import XCTest
@testable import Macsimize

final class MaximizeStrategyTests: XCTestCase {
    func testTargetRectUsesVisibleFrameOfMostOverlappedScreen() {
        let screens = [
            ScreenDescriptor(
                identifier: "left",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 50, width: 1512, height: 900)
            ),
            ScreenDescriptor(
                identifier: "right",
                frame: CGRect(x: 1512, y: 0, width: 1728, height: 1117),
                visibleFrame: CGRect(x: 1512, y: 32, width: 1728, height: 1060)
            )
        ]

        let windowFrame = CGRect(x: 1700, y: 100, width: 800, height: 800)
        XCTAssertEqual(
            MaximizeStrategy.targetRect(for: windowFrame, screens: screens),
            ScreenHelpers.accessibilityRect(forVisibleFrame: screens[1].visibleFrame, in: screens)
        )
    }

    func testTargetRectFallsBackToNearestScreenWhenWindowIsOffScreen() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            ),
            ScreenDescriptor(
                identifier: "secondary",
                frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1040)
            )
        ]

        let offscreenWindow = CGRect(x: 3400, y: 120, width: 600, height: 400)
        XCTAssertEqual(
            MaximizeStrategy.targetRect(for: offscreenWindow, screens: screens),
            ScreenHelpers.accessibilityRect(forVisibleFrame: screens[1].visibleFrame, in: screens)
        )
    }

    func testShouldRestoreWhenWindowAlreadyMatchesMaximizeTarget() {
        let currentFrame = CGRect(x: 0, y: 25, width: 1440, height: 840)
        let targetFrame = CGRect(x: 0, y: 25, width: 1440, height: 840)
        let storedState = StoredWindowFrameState(
            originalFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastAppliedMaximizeFrame: nil
        )

        XCTAssertTrue(MaximizeStrategy.shouldRestore(currentFrame: currentFrame, targetFrame: targetFrame, storedState: storedState))
    }

    func testDoesNotRestoreAfterManualResizeFollowingPreviousMaximize() {
        let targetFrame = CGRect(x: 0, y: 25, width: 1440, height: 840)
        let storedState = StoredWindowFrameState(
            originalFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastAppliedMaximizeFrame: targetFrame
        )
        let manuallyAdjustedFrame = CGRect(x: 40, y: 40, width: 1200, height: 700)

        XCTAssertFalse(MaximizeStrategy.shouldRestore(
            currentFrame: manuallyAdjustedFrame,
            targetFrame: targetFrame,
            storedState: storedState
        ))
    }

    func testRestoresWhenCurrentFrameIsNearLastAppliedMaximizeFrame() {
        let targetFrame = CGRect(x: 0, y: 25, width: 1440, height: 840)
        let lastAppliedMaximizeFrame = CGRect(x: 1, y: 24, width: 1439, height: 841)
        let storedState = StoredWindowFrameState(
            originalFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastAppliedMaximizeFrame: lastAppliedMaximizeFrame
        )

        XCTAssertTrue(MaximizeStrategy.shouldRestore(
            currentFrame: targetFrame,
            targetFrame: targetFrame,
            storedState: storedState
        ))
    }

    func testAccessibilityRectConvertsVisibleFrameIntoTopLeftDesktopCoordinates() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949)
            ),
            ScreenDescriptor(
                identifier: "secondary",
                frame: CGRect(x: 1512, y: 0, width: 1728, height: 1117),
                visibleFrame: CGRect(x: 1512, y: 32, width: 1728, height: 1060)
            )
        ]

        XCTAssertEqual(
            ScreenHelpers.accessibilityRect(forVisibleFrame: screens[0].visibleFrame, in: screens),
            CGRect(x: 0, y: 168, width: 1512, height: 949)
        )
        XCTAssertEqual(
            ScreenHelpers.accessibilityRect(forVisibleFrame: screens[1].visibleFrame, in: screens),
            CGRect(x: 1512, y: 25, width: 1728, height: 1060)
        )
    }
}
