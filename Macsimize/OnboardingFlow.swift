import Foundation

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case permissions
    case preferences
    case completion
}

struct OnboardingFlow: Equatable {
    private(set) var step: OnboardingStep

    init(step: OnboardingStep = .welcome) {
        self.step = step
    }

    @discardableResult
    mutating func advance(permissionsReady: Bool) -> Bool {
        switch step {
        case .welcome:
            step = .permissions
        case .permissions:
            guard permissionsReady else {
                return false
            }
            step = .preferences
        case .preferences:
            step = .completion
        case .completion:
            return false
        }
        return true
    }

    @discardableResult
    mutating func retreat() -> Bool {
        switch step {
        case .permissions:
            step = .welcome
        case .preferences:
            step = .permissions
        case .completion:
            step = .preferences
        case .welcome:
            return false
        }
        return true
    }
}
