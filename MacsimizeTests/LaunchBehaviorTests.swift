import XCTest
@testable import Macsimize

final class LaunchBehaviorTests: XCTestCase {
    func testFreshLaunchRequestsOnboarding() {
        let decision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: false,
                onboardingCompleted: false,
                showSettingsOnStartup: false,
                launchArgumentsRequestSettings: false,
                launchedFromFinder: true,
                needsPermissions: false
            )
        )

        XCTAssertEqual(decision.initialWindowRequest, .onboarding)
        XCTAssertTrue(decision.shouldShowWindow)
        XCTAssertFalse(decision.shouldRequestSettingsFromExistingInstance)
    }

    func testExistingUserFinderLaunchRequestsSettingsFromRunningInstanceWithoutOpeningWindowLocally() {
        let decision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: false,
                onboardingCompleted: true,
                showSettingsOnStartup: false,
                launchArgumentsRequestSettings: false,
                launchedFromFinder: true,
                needsPermissions: false
            )
        )

        XCTAssertEqual(decision.initialWindowRequest, .none)
        XCTAssertFalse(decision.shouldShowWindow)
        XCTAssertTrue(decision.shouldRequestSettingsFromExistingInstance)
    }

    func testStartupPreferenceRequestsSettingsAfterOnboarding() {
        let decision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: false,
                onboardingCompleted: true,
                showSettingsOnStartup: true,
                launchArgumentsRequestSettings: false,
                launchedFromFinder: false,
                needsPermissions: false
            )
        )

        XCTAssertEqual(decision.initialWindowRequest, .settings(explicit: false))
        XCTAssertTrue(decision.shouldShowWindow)
    }

    func testPermissionsRequirementDoesNotAutoOpenSettingsAfterOnboarding() {
        let decision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: false,
                onboardingCompleted: true,
                showSettingsOnStartup: false,
                launchArgumentsRequestSettings: false,
                launchedFromFinder: false,
                needsPermissions: true
            )
        )

        XCTAssertEqual(decision.initialWindowRequest, .none)
        XCTAssertFalse(decision.shouldShowWindow)
    }

    func testExplicitSettingsLaunchStillRequestsSettingsFromExistingInstance() {
        let decision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: false,
                onboardingCompleted: true,
                showSettingsOnStartup: false,
                launchArgumentsRequestSettings: true,
                launchedFromFinder: false,
                needsPermissions: false
            )
        )

        XCTAssertEqual(decision.initialWindowRequest, .settings(explicit: true))
        XCTAssertTrue(decision.shouldRequestSettingsFromExistingInstance)
    }

    func testDevelopmentBuildDoesNotAutoOpenSettingsAfterOnboarding() {
        let decision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: true,
                onboardingCompleted: true,
                showSettingsOnStartup: false,
                launchArgumentsRequestSettings: false,
                launchedFromFinder: false,
                needsPermissions: false
            )
        )

        XCTAssertEqual(decision.initialWindowRequest, .none)
        XCTAssertFalse(decision.shouldShowWindow)
    }
}
