import SwiftUI

struct SettingsRootView: View {
    enum ContentMode {
        case automatic
        case onboarding
        case settings
    }

    let appState: AppState
    let contentMode: ContentMode

    init(appState: AppState, contentMode: ContentMode = .automatic) {
        self.appState = appState
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            switch resolvedMode {
            case .onboarding:
                OnboardingView(appState: appState)
            case .settings:
                PreferencesView(appState: appState)
            case .automatic:
                PreferencesView(appState: appState)
            }
        }
    }

    private var resolvedMode: ContentMode {
        switch contentMode {
        case .automatic:
            appState.settings.shouldPresentOnboarding ? .onboarding : .settings
        case .onboarding, .settings:
            contentMode
        }
    }
}
