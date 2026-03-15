import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var updateManager: UpdateManager

    private let appState: AppState
    @State private var showPermissionsRequiredPopover = false
    @State private var showMenuBarHint = false

    init(appState: AppState) {
        self.appState = appState
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

    private var missingPermissionsMessage: String {
        var missing: [String] = []
        if !permissions.state.accessibilityTrusted {
            missing.append(AppStrings.accessibilityButtonTitle)
        }
        if !permissions.state.inputMonitoringGranted {
            missing.append(AppStrings.inputMonitoringButtonTitle)
        }
        return "Enable \(missing.joined(separator: " and ")) to finish setup."
    }

    var body: some View {
        Group {
            if showMenuBarHint {
                completionView
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    onboardingCard(
                        title: AppStrings.permissionsSectionTitle,
                        description: "\(appDisplayName) needs these permissions to intercept green-button clicks and resize windows."
                    ) {
                        SharedPermissionsSection(appState: appState)
                    }

                    onboardingCard(
                        title: "Start at Login",
                        description: "Choose whether \(appDisplayName) should start automatically when you sign in."
                    ) {
                        SharedLoginItemSection(settings: settings)
                    }

                    onboardingCard(
                        title: AppStrings.updatesSectionTitle,
                        description: "Pick how often \(appDisplayName) should look for updates."
                    ) {
                        SharedUpdatesSection(settings: settings, updateManager: updateManager, style: .onboarding)
                    }

                    HStack {
                        Spacer()

                        Button("Finish Setup") {
                            if permissionsReady {
                                showMenuBarHint = true
                            } else {
                                showPermissionsRequiredPopover = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help(permissionsReady ? "Finish setup" : missingPermissionsMessage)
                        .popover(isPresented: $showPermissionsRequiredPopover, arrowEdge: .top) {
                            Text(missingPermissionsMessage)
                                .padding(12)
                                .frame(width: 280, alignment: .leading)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: permissionsReady) { _, ready in
            if ready {
                showPermissionsRequiredPopover = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to \(appDisplayName)")
                .font(.title2.weight(.semibold))

            Text("Macsimize makes the green button maximize by default, while Option-click keeps native full screen available.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
    }

    private var completionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("You’re all set")
                .font(.title2.weight(.semibold))

            Text("Here is the icon in your menu bar for \(appDisplayName). Use it any time to open Settings or quit \(appDisplayName).")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Image(nsImage: MacsimizeGlyphImage.image(pointSize: 42))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)

                Spacer()
            }
            .padding(.top, 4)

            Spacer()

            HStack {
                Spacer()

                Button("Done") {
                    settings.completeOnboarding()
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func onboardingCard<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
