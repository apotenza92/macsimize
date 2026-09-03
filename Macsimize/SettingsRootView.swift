import SwiftUI

struct SettingsRootView: View {
    enum ContentMode {
        case automatic
        case onboarding
        case settings
    }

    let appState: AppState
    let contentMode: ContentMode
    let contentDidChange: @MainActor () -> Void

    init(
        appState: AppState,
        contentMode: ContentMode = .automatic,
        contentDidChange: @escaping @MainActor () -> Void = {}
    ) {
        self.appState = appState
        self.contentMode = contentMode
        self.contentDidChange = contentDidChange
    }

    var body: some View {
        Group {
            switch resolvedMode {
            case .onboarding:
                OnboardingView(appState: appState, contentDidChange: contentDidChange)
            case .settings:
                PreferencesView(appState: appState, contentDidChange: contentDidChange)
            case .automatic:
                PreferencesView(appState: appState, contentDidChange: contentDidChange)
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
