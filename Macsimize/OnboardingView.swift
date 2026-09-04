import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @State private var openSettingsWhenFinished = false
    private let appState: AppState
    private let onComplete: (Bool) -> Void

    init(appState: AppState, onComplete: @escaping (Bool) -> Void) {
        self.appState = appState
        self.onComplete = onComplete
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPage(
                title: "Welcome to \(AppIdentity.displayName)",
                subtitle: introduction,
                titleIcon: Image(nsImage: MacsimizeGlyphImage.image(pointSize: 40))
            ) {
                VStack(alignment: .leading, spacing: SettingsLayout.controlSpacing) {
                    Text("Enable both permissions to get started.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    RequiredPermissionsList(appState: appState, detailFont: .body)
                }
            }

            VStack(spacing: 0) {
                Divider()
                HStack(spacing: SettingsLayout.controlSpacing) {
                    Toggle("Open Settings when finished", isOn: $openSettingsWhenFinished)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.subheadline)
                    Spacer()
                    Button("Get Started") {
                        permissions.refresh(promptIfNeeded: false)
                        guard permissions.state.allRequiredPermissionsGranted else { return }
                        settings.completeOnboarding()
                        onComplete(openSettingsWhenFinished)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.state.allRequiredPermissionsGranted)
                }
                .padding(.horizontal, SettingsLayout.horizontalPadding)
                .padding(.vertical, SettingsLayout.controlSpacing)
            }
            .fixedSize(horizontal: false, vertical: true)
            .reportSettingsContentHeight()
        }
        .frame(width: SettingsLayout.detailWidth)
        .frame(minHeight: 180, idealHeight: SettingsLayout.defaultSettingsHeight, maxHeight: .infinity)
        .onAppear {
            settings.beginOnboarding()
            permissions.refresh(promptIfNeeded: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh(promptIfNeeded: false)
        }
    }

    private var introduction: String {
        switch settings.selectedAction {
        case .maximize:
            "Click the green button to \(AppStrings.maximizeModeTitle.lowercased()) windows. \(AppStrings.maximizeModeHelp)"
        case .fullScreen:
            "Click the green button to enter Full Screen. \(AppStrings.fullScreenModeHelp)"
        }
    }
}
