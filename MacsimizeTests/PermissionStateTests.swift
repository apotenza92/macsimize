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

        XCTAssertEqual(state.summary, AppStrings.permissionSummaryAccessibilityRequired)
        XCTAssertTrue(state.hasVisibleIssue)
    }

    func testSummaryShowsInputMonitoringWhenAccessibilityIsGranted() {
        let state = PermissionState(
            accessibilityTrusted: true,
            inputMonitoringGranted: false,
            secureEventInputEnabled: false,
            eventTapRunning: false,
            lastFailureReason: nil
        )

        XCTAssertEqual(state.summary, AppStrings.permissionSummaryInputMonitoringRequired)
        XCTAssertTrue(state.hasVisibleIssue)
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
        XCTAssertTrue(state.hasVisibleIssue)
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
        XCTAssertTrue(state.detail.contains(AppStrings.permissionDetailAccessibilityRequired))
        XCTAssertTrue(state.hasVisibleIssue)
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
        XCTAssertTrue(state.hasVisibleIssue)
    }

    func testHasVisibleIssueIsFalseWhenPermissionsAndEventTapAreReady() {
        let state = PermissionState(
            accessibilityTrusted: true,
            inputMonitoringGranted: true,
            secureEventInputEnabled: false,
            eventTapRunning: true,
            lastFailureReason: nil
        )

        XCTAssertFalse(state.hasVisibleIssue)
    }
}
