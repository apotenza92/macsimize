import SwiftUI

struct SettingsRootView: View {
    enum ContentMode: Hashable {
        case automatic
        case onboarding
        case settings
    }

    let appState: AppState
    let contentMode: ContentMode
    let contentHeightDidChange: @MainActor (CGFloat) -> Void
    let onboardingCompleted: @MainActor (Bool) -> Void

    init(
        appState: AppState,
        contentMode: ContentMode = .automatic,
        contentHeightDidChange: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onboardingCompleted: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.appState = appState
        self.contentMode = contentMode
        self.contentHeightDidChange = contentHeightDidChange
        self.onboardingCompleted = onboardingCompleted
    }

    var body: some View {
        Group {
            switch resolvedMode {
            case .onboarding:
                OnboardingView(appState: appState, onComplete: onboardingCompleted)
            case .settings:
                PreferencesView(appState: appState)
            case .automatic:
                PreferencesView(appState: appState)
            }
        }
        .onPreferenceChange(SettingsContentHeightKey.self) { height in
            DispatchQueue.main.async { contentHeightDidChange(height) }
        }
        // Recreate the measurement listener when replacing the initial automatic view.
        .id(contentMode)
        .font(.body)
        .controlSize(.regular)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
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

// Sum the scrolling content and any pinned navigation footer, never the viewport.
struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

extension View {
    func reportSettingsContentHeight() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: SettingsContentHeightKey.self, value: geometry.size.height)
            }
        }
    }
}
