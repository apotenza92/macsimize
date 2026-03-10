import XCTest
@testable import Macsimize

final class UpdateManagerTests: XCTestCase {
    func testStatusMessageReturnsUpToDateForNoUpdateSparkleError() {
        let error = NSError(domain: SUSparkleErrorDomain, code: 1001)

        XCTAssertEqual(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: "Checking for updates..."),
            "Up to date."
        )
    }

    func testStatusMessageReturnsNilForInstallationCanceledError() {
        let error = NSError(domain: SUSparkleErrorDomain, code: 4007)

        XCTAssertNil(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: "Checking for updates...")
        )
    }

    func testStatusMessageDoesNotOverrideAvailableUpdateMessage() {
        let error = NSError(domain: "com.example.failure", code: 1)

        XCTAssertNil(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: "Update available: 1.2.3")
        )
    }

    func testStatusMessageReturnsFailureWhenStillCheckingAndErrorIsReal() {
        let error = NSError(domain: "com.example.failure", code: 1)

        XCTAssertEqual(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: "Checking for updates..."),
            "Unable to check for updates."
        )
    }
}
