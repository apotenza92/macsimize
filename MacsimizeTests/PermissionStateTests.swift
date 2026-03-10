import XCTest
@testable import Macsimize

final class PermissionStateTests: XCTestCase {
    func testSummaryPrefersAccessibilityFirst() {
        let state = PermissionState(
            accessibilityTrusted: false,
            inputMonitoringGranted: false,
            secureEventInputEnabled: false,
            eventTapRunning: false,
            lastFailureReason: nil
        )

        XCTAssertEqual(state.summary, "Accessibility required")
    }

    func testSummaryShowsInputMonitoringWhenAccessibilityIsGranted() {
        let state = PermissionState(
            accessibilityTrusted: true,
            inputMonitoringGranted: false,
            secureEventInputEnabled: false,
            eventTapRunning: false,
            lastFailureReason: nil
        )

        XCTAssertEqual(state.summary, "Input Monitoring required")
    }

    func testDetailMentionsSecureEventInputWhenPermissionsGranted() {
        let state = PermissionState(
            accessibilityTrusted: true,
            inputMonitoringGranted: true,
            secureEventInputEnabled: true,
            eventTapRunning: false,
            lastFailureReason: nil
        )

        XCTAssertTrue(state.detail.contains("Secure Event Input"))
    }

    func testDetailWarnsThatNativeBehaviorContinuesWithoutAccessibility() {
        let state = PermissionState(
            accessibilityTrusted: false,
            inputMonitoringGranted: false,
            secureEventInputEnabled: false,
            eventTapRunning: false,
            lastFailureReason: nil
        )

        XCTAssertTrue(state.detail.contains("cannot intercept the green button"))
        XCTAssertTrue(state.detail.contains("normal behavior"))
    }

    func testDetailExplainsEventTapMustBeRunningAfterPermissionsGranted() {
        let state = PermissionState(
            accessibilityTrusted: true,
            inputMonitoringGranted: true,
            secureEventInputEnabled: false,
            eventTapRunning: false,
            lastFailureReason: nil
        )

        XCTAssertTrue(state.detail.contains("event tap is not running yet"))
        XCTAssertTrue(state.detail.contains("not active"))
    }
}
