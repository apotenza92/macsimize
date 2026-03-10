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
            restoreFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastManagedMaximizeFrame: nil
        )

        XCTAssertTrue(MaximizeStrategy.shouldRestore(currentFrame: currentFrame, targetFrame: targetFrame, storedState: storedState))
    }

    func testDoesNotRestoreAfterManualResizeFollowingPreviousMaximize() {
        let targetFrame = CGRect(x: 0, y: 25, width: 1440, height: 840)
        let storedState = StoredWindowFrameState(
            restoreFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastManagedMaximizeFrame: targetFrame
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
            restoreFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastManagedMaximizeFrame: lastAppliedMaximizeFrame
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

    func testDragRestoreFrameKeepsCursorInsideRestoredFrame() {
        let currentFrame = CGRect(x: 0, y: 25, width: 1440, height: 840)
        let restoreFrame = CGRect(x: 100, y: 120, width: 900, height: 700)
        let cursorLocation = CGPoint(x: 1300, y: 200)

        let destination = MaximizeStrategy.dragRestoreFrame(
            currentFrame: currentFrame,
            restoreFrame: restoreFrame,
            cursorLocation: cursorLocation
        )

        XCTAssertEqual(destination.size, restoreFrame.size)
        XCTAssertEqual(destination.minY, currentFrame.minY)
        XCTAssertTrue(destination.contains(cursorLocation))
    }

    func testResolvedRestoreFrameReturnsExactStoredFrameWhenVisible() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            )
        ]
        let storedState = StoredWindowFrameState(
            restoreFrame: CGRect(x: 100, y: 120, width: 900, height: 700),
            lastManagedMaximizeFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
        )

        let resolution = MaximizeStrategy.resolvedRestoreFrame(
            currentFrame: CGRect(x: 0, y: 25, width: 1440, height: 840),
            storedState: storedState,
            screens: screens
        )

        XCTAssertEqual(resolution, RestoreFrameResolution(frame: storedState.restoreFrame, wasClamped: false))
    }

    func testResolvedRestoreFrameClampsOriginIntoVisibleFrame() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            )
        ]
        let storedState = StoredWindowFrameState(
            restoreFrame: CGRect(x: 1300, y: -50, width: 400, height: 600),
            lastManagedMaximizeFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
        )

        let resolution = MaximizeStrategy.resolvedRestoreFrame(
            currentFrame: CGRect(x: 0, y: 25, width: 1440, height: 840),
            storedState: storedState,
            screens: screens
        )

        XCTAssertEqual(resolution?.frame, CGRect(x: 1040, y: 35, width: 400, height: 600))
        XCTAssertEqual(resolution?.wasClamped, true)
    }

    func testResolvedRestoreFrameCapsSizeToVisibleFrame() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            )
        ]
        let storedState = StoredWindowFrameState(
            restoreFrame: CGRect(x: 10, y: 0, width: 1700, height: 1000),
            lastManagedMaximizeFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
        )

        let resolution = MaximizeStrategy.resolvedRestoreFrame(
            currentFrame: CGRect(x: 0, y: 25, width: 1440, height: 840),
            storedState: storedState,
            screens: screens
        )

        XCTAssertEqual(resolution?.frame, CGRect(x: 0, y: 35, width: 1440, height: 840))
        XCTAssertEqual(resolution?.wasClamped, true)
    }

    func testResolvedRestoreFrameFallsBackToCurrentManagedScreenWhenOriginalScreenIsGone() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            ),
            ScreenDescriptor(
                identifier: "secondary",
                frame: CGRect(x: 1440, y: 0, width: 1728, height: 1117),
                visibleFrame: CGRect(x: 1440, y: 32, width: 1728, height: 1060)
            )
        ]
        let storedState = StoredWindowFrameState(
            restoreFrame: CGRect(x: 4000, y: 300, width: 900, height: 700),
            lastManagedMaximizeFrame: CGRect(x: 1440, y: 25, width: 1728, height: 1060)
        )

        let resolution = MaximizeStrategy.resolvedRestoreFrame(
            currentFrame: CGRect(x: 1440, y: 25, width: 1728, height: 1060),
            storedState: storedState,
            screens: screens
        )

        XCTAssertEqual(resolution?.frame, CGRect(x: 2268, y: 300, width: 900, height: 700))
        XCTAssertEqual(resolution?.wasClamped, true)
    }

    func testResolvedRestoreFrameUsesClampedDragRestoreDestination() {
        let screens = [
            ScreenDescriptor(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
            )
        ]
        let storedState = StoredWindowFrameState(
            restoreFrame: CGRect(x: 100, y: 120, width: 1200, height: 700),
            lastManagedMaximizeFrame: CGRect(x: 0, y: 25, width: 1440, height: 840)
        )

        let resolution = MaximizeStrategy.resolvedRestoreFrame(
            currentFrame: CGRect(x: 0, y: 25, width: 1440, height: 840),
            storedState: storedState,
            screens: screens,
            cursorLocation: CGPoint(x: 1435, y: 80)
        )

        XCTAssertEqual(resolution?.frame, CGRect(x: 240, y: 35, width: 1200, height: 700))
        XCTAssertEqual(resolution?.wasClamped, true)
    }
}
