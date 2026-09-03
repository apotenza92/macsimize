import XCTest
@testable import Macsimize

final class LaunchBehaviorTests: XCTestCase {
    func testOnboardingAdvancesThroughTheFourSteps() {
        var flow = OnboardingFlow()

        XCTAssertEqual(flow.step, .welcome)
        XCTAssertTrue(flow.advance(permissionsReady: false))
        XCTAssertEqual(flow.step, .permissions)
        XCTAssertTrue(flow.advance(permissionsReady: true))
        XCTAssertEqual(flow.step, .preferences)
        XCTAssertTrue(flow.advance(permissionsReady: true))
        XCTAssertEqual(flow.step, .completion)
        XCTAssertFalse(flow.advance(permissionsReady: true))
    }

    func testOnboardingCannotPassPermissionsUntilBothAreGranted() {
        var flow = OnboardingFlow(step: .permissions)

        XCTAssertFalse(flow.advance(permissionsReady: false))
        XCTAssertEqual(flow.step, .permissions)
    }

    func testOnboardingBackNavigationReturnsFromCompletionToWelcome() {
        var flow = OnboardingFlow(step: .completion)

        XCTAssertTrue(flow.retreat())
        XCTAssertEqual(flow.step, .preferences)
        XCTAssertTrue(flow.retreat())
        XCTAssertEqual(flow.step, .permissions)
        XCTAssertTrue(flow.retreat())
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertFalse(flow.retreat())
    }

    @MainActor
    func testContentSizeIsCappedOnlyWhenItExceedsTheDisplay() {
        XCTAssertEqual(
            SettingsWindowController.contentSize(
                fittingSize: NSSize(width: 640, height: 480),
                maximumSize: NSSize(width: 1_200, height: 800)
            ),
            NSSize(width: 640, height: 480)
        )
        XCTAssertEqual(
            SettingsWindowController.contentSize(
                fittingSize: NSSize(width: 1_600, height: 1_000),
                maximumSize: NSSize(width: 1_200, height: 800)
            ),
            NSSize(width: 1_200, height: 800)
        )
    }

    @MainActor
    func testOnboardingFrameIsCenteredInActiveDisplayVisibleArea() {
        let visibleFrame = NSRect(x: 1_440, y: 40, width: 1_920, height: 1_040)

        let frame = SettingsWindowController.centeredFrame(
            size: NSSize(width: 420, height: 580),
            in: visibleFrame
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(frame.midY, visibleFrame.midY)
    }

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
