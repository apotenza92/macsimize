import XCTest
import Sparkle
@testable import Macsimize

final class UpdateManagerTests: XCTestCase {
    func testStatusMessageReturnsUpToDateForNoUpdateSparkleError() {
        let error = NSError(domain: SUSparkleErrorDomain, code: 1001)

        XCTAssertEqual(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: AppStrings.updateCheckingStatusMessage),
            AppStrings.updateUpToDateStatusMessage
        )
    }

    func testStatusMessageReturnsNilForInstallationCanceledError() {
        let error = NSError(domain: SUSparkleErrorDomain, code: 4007)

        XCTAssertNil(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: AppStrings.updateCheckingStatusMessage)
        )
    }

    func testStatusMessageDoesNotOverrideAvailableUpdateMessage() {
        let error = NSError(domain: "com.example.failure", code: 1)

        XCTAssertNil(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: AppStrings.updateAvailable(version: "1.2.3"))
        )
    }

    func testStatusMessageReturnsFailureWhenStillCheckingAndErrorIsReal() {
        let error = NSError(domain: "com.example.failure", code: 1)

        XCTAssertEqual(
            UpdateManager.statusMessage(forSparkleError: error, currentStatusMessage: AppStrings.updateCheckingStatusMessage),
            AppStrings.updateCheckFailedStatusMessage
        )
    }
}
