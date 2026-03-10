import ApplicationServices
import XCTest
@testable import Macsimize

final class AccessibilityServiceCurrentSpaceTests: XCTestCase {
    func testCurrentActiveSpaceIDsCollectsLayerZeroOnscreenEntries() {
        let entries: [[String: AnyObject]] = [
            [
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowNumber as String: NSNumber(value: 11)
            ],
            [
                kCGWindowLayer as String: NSNumber(value: 3),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowNumber as String: NSNumber(value: 99)
            ]
        ]

        let spaceIDs = AccessibilityService.currentActiveSpaceIDs(entries: entries) { windowID in
            windowID == 11 ? [4, 5] : [8]
        }

        XCTAssertEqual(spaceIDs, [4, 5])
    }

    func testCurrentSpaceCandidateIncludedWhenSpacesIntersect() {
        let candidate = Self.makeCandidate(spaceIDs: [2], isOnScreen: false)

        XCTAssertTrue(
            AccessibilityService.shouldIncludeCurrentSpaceStandardCandidate(
                candidate,
                activeSpaceIDs: [2, 3]
            )
        )
    }

    func testCurrentSpaceCandidateExcludedWhenSpacesDoNotIntersect() {
        let candidate = Self.makeCandidate(spaceIDs: [9], isOnScreen: true)

        XCTAssertFalse(
            AccessibilityService.shouldIncludeCurrentSpaceStandardCandidate(
                candidate,
                activeSpaceIDs: [2, 3]
            )
        )
    }

    func testCurrentSpaceCandidateFallsBackToOnScreenWhenNoSpacesResolved() {
        let candidate = Self.makeCandidate(spaceIDs: [], isOnScreen: true)

        XCTAssertTrue(
            AccessibilityService.shouldIncludeCurrentSpaceStandardCandidate(
                candidate,
                activeSpaceIDs: []
            )
        )
    }

    func testCurrentSpaceCandidateExcludesMinimizedWindows() {
        let candidate = Self.makeCandidate(spaceIDs: [2], isOnScreen: true, isMinimized: true)

        XCTAssertFalse(
            AccessibilityService.shouldIncludeCurrentSpaceStandardCandidate(
                candidate,
                activeSpaceIDs: [2]
            )
        )
    }

    func testCurrentSpaceCGEntriesFiltersToLayerZeroEntriesInActiveSpace() {
        let entries: [[String: AnyObject]] = [
            [
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowNumber as String: NSNumber(value: 11),
                kCGWindowOwnerPID as String: NSNumber(value: 100),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 10),
                    "Y": NSNumber(value: 10),
                    "Width": NSNumber(value: 500),
                    "Height": NSNumber(value: 400)
                ] as NSDictionary
            ],
            [
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowNumber as String: NSNumber(value: 12),
                kCGWindowOwnerPID as String: NSNumber(value: 101),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 20),
                    "Y": NSNumber(value: 20),
                    "Width": NSNumber(value: 500),
                    "Height": NSNumber(value: 400)
                ] as NSDictionary
            ],
            [
                kCGWindowLayer as String: NSNumber(value: 2),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowNumber as String: NSNumber(value: 13),
                kCGWindowOwnerPID as String: NSNumber(value: 102)
            ]
        ]

        let filtered = AccessibilityService.currentSpaceCGEntries(
            entries: entries,
            activeSpaceIDs: [2]
        ) { windowID in
            switch windowID {
            case 11:
                return [2]
            case 12:
                return [9]
            default:
                return []
            }
        }

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual((filtered.first?[kCGWindowNumber as String] as? NSNumber)?.intValue, 11)
    }

    func testMatchesRequestedIdentifierPassesWhenNoFilterSupplied() {
        XCTAssertTrue(AccessibilityService.matchesRequestedIdentifier("window-1", matchingIdentifiers: nil))
    }

    func testMatchesRequestedIdentifierFiltersToRequestedSet() {
        XCTAssertTrue(
            AccessibilityService.matchesRequestedIdentifier(
                "window-1",
                matchingIdentifiers: ["window-1", "window-2"]
            )
        )
        XCTAssertFalse(
            AccessibilityService.matchesRequestedIdentifier(
                "window-3",
                matchingIdentifiers: ["window-1", "window-2"]
            )
        )
    }

    func testMakeWindowIdentifierPrefersCGWindowIDOverWindowNumberAndTitle() {
        XCTAssertEqual(
            AccessibilityService.makeWindowIdentifier(
                pid: 42,
                cgWindowID: 321,
                windowNumber: 123,
                title: "New Tab"
            ),
            "pid:42-cgwindow:321"
        )
    }

    func testMakeWindowIdentifierFallsBackToWindowNumberWhenCGWindowIDUnavailable() {
        XCTAssertEqual(
            AccessibilityService.makeWindowIdentifier(
                pid: 42,
                cgWindowID: nil,
                windowNumber: 123,
                title: "New Tab"
            ),
            "pid:42-window:123"
        )
    }

    func testMakeWindowIdentifierFallsBackToTitleWhenNoWindowIDIsAvailable() {
        XCTAssertEqual(
            AccessibilityService.makeWindowIdentifier(
                pid: 42,
                cgWindowID: nil,
                windowNumber: nil,
                title: "New Tab"
            ),
            "pid:42-title:New Tab"
        )
    }

    func testTitleBarRectAnchorsToTopOfWindow() {
        let windowFrame = CGRect(x: 100, y: 200, width: 900, height: 700)
        let controlFrame = CGRect(x: 112, y: 215, width: 14, height: 14)

        let rect = AccessibilityService.titleBarRect(
            forWindowFrame: windowFrame,
            controlFrame: controlFrame
        )

        XCTAssertEqual(rect.minX, windowFrame.minX)
        XCTAssertEqual(rect.width, windowFrame.width)
        XCTAssertEqual(rect.minY, windowFrame.minY, accuracy: 0.001)
        XCTAssertEqual(rect.height, 44, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 244, accuracy: 0.001)
    }

    func testFallbackTitleBarRectAnchorsToTopOfWindow() {
        let windowFrame = CGRect(x: 50, y: 75, width: 600, height: 400)

        let rect = AccessibilityService.fallbackTitleBarRect(
            forWindowFrame: windowFrame,
            fallbackTitleBarHeight: 56
        )

        XCTAssertEqual(rect.minX, windowFrame.minX)
        XCTAssertEqual(rect.width, windowFrame.width)
        XCTAssertEqual(rect.minY, windowFrame.minY)
        XCTAssertEqual(rect.height, 56, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 131, accuracy: 0.001)
    }

    func testTitleBarSupplementaryFrameRejectsFullWindowSizedGroup() {
        let windowFrame = CGRect(x: 50, y: 75, width: 600, height: 400)
        let frame = windowFrame

        XCTAssertFalse(
            AccessibilityService.isLikelyTitleBarSupplementaryFrame(
                frame,
                in: windowFrame
            )
        )
    }

    func testTitleBarSupplementaryFrameAcceptsTopAttachedToolbar() {
        let windowFrame = CGRect(x: 50, y: 75, width: 600, height: 400)
        let frame = CGRect(x: 50, y: 75, width: 600, height: 44)

        XCTAssertTrue(
            AccessibilityService.isLikelyTitleBarSupplementaryFrame(
                frame,
                in: windowFrame
            )
        )
    }

    private static func makeCandidate(
        spaceIDs: Set<Int>,
        isOnScreen: Bool,
        isMinimized: Bool = false
    ) -> WindowCandidate {
        WindowCandidate(
            axWindow: AXUIElementCreateSystemWide(),
            cgWindowID: 1,
            bounds: CGRect(x: 0, y: 0, width: 600, height: 400),
            layer: 0,
            alpha: 1,
            isOnScreen: isOnScreen,
            subrole: nil,
            spaceIDs: spaceIDs,
            isMinimized: isMinimized
        )
    }
}
