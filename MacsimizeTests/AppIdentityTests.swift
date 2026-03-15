import XCTest
@testable import Macsimize

final class AppIdentityTests: XCTestCase {
    func testRunningIdentityRecognizesStableBetaAndDevelopmentBuilds() {
        XCTAssertEqual(AppIdentity.runningIdentity(bundleIdentifier: AppIdentity.stableBundleIdentifier), .stable)
        XCTAssertEqual(AppIdentity.runningIdentity(bundleIdentifier: AppIdentity.betaBundleIdentifier), .beta)
        XCTAssertEqual(AppIdentity.runningIdentity(bundleIdentifier: AppIdentity.developmentBundleIdentifier), .development)
        XCTAssertEqual(AppIdentity.runningIdentity(bundleIdentifier: "com.example.unknown"), .unknown)
    }

    func testCapabilitiesAndUpdateChannelsMatchIdentity() {
        XCTAssertTrue(AppIdentity.supportsUpdates(bundleIdentifier: AppIdentity.stableBundleIdentifier))
        XCTAssertTrue(AppIdentity.supportsUpdates(bundleIdentifier: AppIdentity.betaBundleIdentifier))
        XCTAssertFalse(AppIdentity.supportsUpdates(bundleIdentifier: AppIdentity.developmentBundleIdentifier))

        XCTAssertTrue(AppIdentity.supportsLoginItem(bundleIdentifier: AppIdentity.stableBundleIdentifier))
        XCTAssertTrue(AppIdentity.supportsLoginItem(bundleIdentifier: AppIdentity.betaBundleIdentifier))
        XCTAssertFalse(AppIdentity.supportsLoginItem(bundleIdentifier: AppIdentity.developmentBundleIdentifier))

        XCTAssertEqual(AppIdentity.updateChannelName(bundleIdentifier: AppIdentity.stableBundleIdentifier), "stable")
        XCTAssertEqual(AppIdentity.updateChannelName(bundleIdentifier: AppIdentity.betaBundleIdentifier), "beta")
        XCTAssertNil(AppIdentity.updateChannelName(bundleIdentifier: AppIdentity.developmentBundleIdentifier))
    }

    func testDisplayNameHelpersStillPreferBundleDisplayNameAndFallbacks() {
        XCTAssertEqual(
            AppIdentity.displayName(
                bundleDisplayName: "Macsimize Beta",
                bundleName: "Macsimize",
                bundleURL: URL(fileURLWithPath: "/Applications/Macsimize.app"),
                executableName: "Macsimize"
            ),
            "Macsimize Beta"
        )

        XCTAssertEqual(
            AppIdentity.displayName(
                bundleDisplayName: nil,
                bundleName: nil,
                bundleURL: URL(fileURLWithPath: "/Applications/Macsimize Dev.app"),
                executableName: "Macsimize Dev"
            ),
            "Macsimize Dev"
        )

        XCTAssertEqual(
            AppIdentity.displayName(
                bundleDisplayName: "   ",
                bundleName: nil,
                bundleURL: nil,
                executableName: ""
            ),
            "Macsimize"
        )
    }
}
