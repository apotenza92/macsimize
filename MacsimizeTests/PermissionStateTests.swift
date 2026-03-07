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
}
