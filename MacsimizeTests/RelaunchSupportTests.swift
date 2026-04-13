import XCTest
@testable import Macsimize

final class RelaunchSupportTests: XCTestCase {
    func testAutomaticRelaunchAttemptDefaultsToZero() {
        XCTAssertEqual(RelaunchSupport.automaticRelaunchAttempt(arguments: []), 0)
        XCTAssertEqual(RelaunchSupport.automaticRelaunchAttempt(arguments: ["--settings"]), 0)
    }

    func testAutomaticRelaunchAttemptParsesKnownArgument() {
        XCTAssertEqual(
            RelaunchSupport.automaticRelaunchAttempt(
                arguments: ["--settings", "--macsimize-relaunch-attempt=2"]
            ),
            2
        )
    }

    func testLaunchArgumentsPreserveSettingsRequestAndReplaceRelaunchAttempt() {
        XCTAssertEqual(
            RelaunchSupport.launchArguments(
                from: ["Macsimize Dev", "--settings", "--macsimize-relaunch-attempt=1", "-psn_0_12345"],
                openSettingsArguments: ["--settings", "-settings", "--open-settings"],
                nextAutomaticRelaunchAttempt: 2
            ),
            ["--settings", "--macsimize-relaunch-attempt=2"]
        )
    }

    func testLaunchArgumentsCanOmitAutomaticRelaunchAttempt() {
        XCTAssertEqual(
            RelaunchSupport.launchArguments(
                from: ["Macsimize Dev", "--open-settings"],
                openSettingsArguments: ["--settings", "-settings", "--open-settings"],
                nextAutomaticRelaunchAttempt: nil
            ),
            ["--open-settings"]
        )
    }
}
