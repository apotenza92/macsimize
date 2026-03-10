import XCTest
@testable import Macsimize

final class UpdateManagerTests: XCTestCase {
    func testFinalCycleStatusMessageDoesNotOverrideUpToDateMessage() {
        XCTAssertNil(UpdateManager.finalCycleStatusMessage(currentStatusMessage: "Up to date."))
    }

    func testFinalCycleStatusMessageDoesNotOverrideAvailableUpdateMessage() {
        XCTAssertNil(UpdateManager.finalCycleStatusMessage(currentStatusMessage: "Update available: 1.2.3"))
    }

    func testFinalCycleStatusMessageReturnsFailureWhenStillChecking() {
        XCTAssertEqual(
            UpdateManager.finalCycleStatusMessage(currentStatusMessage: "Checking for updates..."),
            "Unable to check for updates."
        )
    }
}
