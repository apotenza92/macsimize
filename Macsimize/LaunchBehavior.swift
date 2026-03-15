import Foundation

struct LaunchBehaviorInput: Equatable {
    let isDevelopmentBuild: Bool
    let onboardingCompleted: Bool
    let showSettingsOnStartup: Bool
    let launchArgumentsRequestSettings: Bool
    let launchedFromFinder: Bool
    let needsPermissions: Bool
}

enum InitialWindowRequest: Equatable {
    case none
    case onboarding
    case settings(explicit: Bool)
}

struct LaunchBehaviorDecision: Equatable {
    let initialWindowRequest: InitialWindowRequest
    let shouldRequestSettingsFromExistingInstance: Bool

    var shouldShowWindow: Bool {
        initialWindowRequest != .none
    }
}

enum LaunchBehavior {
    static func decide(_ input: LaunchBehaviorInput) -> LaunchBehaviorDecision {
        let explicitSettingsRequest = input.launchArgumentsRequestSettings

        let initialWindowRequest: InitialWindowRequest
        if !input.onboardingCompleted {
            initialWindowRequest = .onboarding
        } else if explicitSettingsRequest || input.showSettingsOnStartup {
            initialWindowRequest = .settings(explicit: explicitSettingsRequest)
        } else {
            initialWindowRequest = .none
        }

        let shouldRequestSettingsFromExistingInstance = explicitSettingsRequest
            || (input.launchedFromFinder && input.onboardingCompleted)

        return LaunchBehaviorDecision(
            initialWindowRequest: initialWindowRequest,
            shouldRequestSettingsFromExistingInstance: shouldRequestSettingsFromExistingInstance
        )
    }
}
