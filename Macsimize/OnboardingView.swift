import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var updateManager: UpdateManager

    private let appState: AppState
    private let contentDidChange: @MainActor () -> Void
    @State private var flow = OnboardingFlow()

    init(appState: AppState, contentDidChange: @escaping @MainActor () -> Void = {}) {
        self.appState = appState
        self.contentDidChange = contentDidChange
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _updateManager = ObservedObject(wrappedValue: appState.updateManager)
    }

    private var appDisplayName: String {
        AppIdentity.displayName
    }

    private var permissionsReady: Bool {
        permissions.state.allRequiredPermissionsGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent

            Divider()

            navigationBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .welcome:
            welcomeStep
        case .permissions:
            permissionsStep
        case .preferences:
            preferencesStep
        case .completion:
            completionStep
        }
    }

    private var welcomeStep: some View {
        SettingsPage(
            title: "Welcome to \(appDisplayName)",
            subtitle: "Make the green button maximize windows without giving up native full screen."
        ) {
            Image(nsImage: MacsimizeGlyphImage.image(pointSize: NSFont.systemFontSize * 3))
                .renderingMode(.template)
                .foregroundStyle(.tint)

            SettingsSection(
                title: "What you can do",
                subtitle: "Use the green button naturally while keeping full screen available."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsInfoRow(
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        title: "Click to maximize",
                        detail: "A normal green-button click fills the usable display."
                    )

                    Divider()

                    SettingsInfoRow(
                        systemImage: "option",
                        title: "Option-click for full screen",
                        detail: "Native macOS full screen stays one modifier key away."
                    )

                    Divider()

                    SettingsInfoRow(
                        systemImage: "arrow.uturn.backward",
                        title: "Click again to restore",
                        detail: "Return a window to the size and position it had before."
                    )
                }
            }
        }
    }

    private var permissionsStep: some View {
        SettingsPage(
            title: "Allow window control",
            subtitle: "\(appDisplayName) needs two macOS permissions to detect green-button clicks and resize windows."
        ) {
            RequiredPermissionsList(appState: appState)

            Label(
                permissionsReady ? "Required permissions are enabled." : "Enable both permissions to continue.",
                systemImage: permissionsReady ? "checkmark.circle.fill" : "info.circle"
            )
            .foregroundStyle(permissionsReady ? .green : .secondary)
        }
    }

    private var preferencesStep: some View {
        SettingsPage(
            title: "Choose your defaults",
            subtitle: "You can change these preferences at any time from the menu bar."
        ) {
            SettingsSection(
                title: "Startup",
                subtitle: "Choose whether \(appDisplayName) opens when you sign in."
            ) {
                SharedLoginItemSection(settings: settings)
            }

            Divider()

            SettingsSection(
                title: "Updates",
                subtitle: "Keep \(appDisplayName) current automatically."
            ) {
                SharedUpdatesSection(
                    settings: settings,
                    updateManager: updateManager
                )
            }
        }
    }

    private var completionStep: some View {
        SettingsPage(
            title: "You’re ready",
            subtitle: "\(appDisplayName) is set up and ready to manage green-button clicks."
        ) {
            Image(nsImage: MacsimizeGlyphImage.image(pointSize: NSFont.systemFontSize * 3))
                .renderingMode(.template)
                .foregroundStyle(.primary)

            SettingsInfoRow(
                title: "Find \(appDisplayName) in the menu bar",
                detail: "Open Settings, maximize all windows, restore windows, or quit from there."
            )
        }
    }

    private var navigationBar: some View {
        HStack {
            Text("Step \(flow.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if flow.step != .welcome {
                Button("Back") {
                    if flow.retreat() {
                        scheduleContentRefit()
                    }
                }
            }

            if flow.step == .completion {
                Button("Done") {
                    settings.completeOnboarding()
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button(flow.step == .welcome ? "Get Started" : "Continue") {
                    if flow.advance(permissionsReady: permissionsReady) {
                        scheduleContentRefit()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(flow.step == .permissions && !permissionsReady)
            }
        }
    }

    private func scheduleContentRefit() {
        DispatchQueue.main.async {
            contentDidChange()
        }
    }
}
