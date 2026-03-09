import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var updateManager: UpdateManager

    private let appState: AppState
    private let preferredContentWidth: CGFloat = 500
    private let horizontalPadding: CGFloat = 20
    private let contentFont: Font = .system(size: 14)
    private let sectionTitleFont: Font = .system(size: 14, weight: .semibold)

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _updateManager = ObservedObject(wrappedValue: appState.updateManager)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            generalSection
            behaviorSection
            updatesSection
            permissionsSection
        }
        .padding(horizontalPadding)
        .font(contentFont)
        .frame(width: preferredContentWidth, alignment: .topLeading)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(sectionTitleFont)

            checkboxRow("Show settings on startup", isOn: $settings.showSettingsOnStartup)
            checkboxRow("Start Macsimize at login", isOn: $settings.startAtLogin)

            HStack(spacing: 12) {
                Button("Restart") {
                    appState.restartApp()
                }
                .buttonStyle(.bordered)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)

                Button("About") {
                    appState.showAboutPanel()
                }
                .buttonStyle(.bordered)

                Button(action: openGitHubPage) {
                    Image("GitHubMark")
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.bordered)
                .help("Open Macsimize on GitHub")
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(sectionTitleFont)

            VStack(alignment: .leading, spacing: 8) {
                permissionActionButton(
                    title: "Accessibility",
                    granted: permissions.state.accessibilityTrusted,
                    action: appState.openAccessibilitySettings
                )
                permissionActionButton(
                    title: "Input Monitoring",
                    granted: permissions.state.inputMonitoringGranted,
                    action: appState.openInputMonitoringSettings
                )
            }

            Text("Macsimize needs Accessibility and Input Monitoring to intercept the green button reliably.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates")
                .font(sectionTitleFont)

            HStack(alignment: .center, spacing: 12) {
                Button("Check for Updates", action: updateManager.checkForUpdates)
                    .buttonStyle(.borderedProminent)
                    .disabled(!updateManager.canCheckForUpdates)

                Picker("Check frequency", selection: $settings.updateCheckFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Behaviour")
                .font(sectionTitleFont)

            Text("Green button click")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 10) {
                ForEach(WindowActionMode.allCases) { mode in
                    actionModeButton(mode)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(settings.selectedAction.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkboxRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
    }

    private func permissionActionButton(
        title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button(title, action: action)
                .buttonStyle(.bordered)
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(granted ? .green : .orange)
                .frame(width: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionModeButton(_ mode: WindowActionMode) -> some View {
        if settings.selectedAction == mode {
            Button(mode.displayName) {
                settings.selectedAction = mode
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .controlSize(.regular)
        } else {
            Button(mode.displayName) {
                settings.selectedAction = mode
            }
            .buttonStyle(BorderedButtonStyle())
            .controlSize(.regular)
        }
    }

    private func openGitHubPage() {
        guard let url = URL(string: "https://github.com/apotenza92/macsimize") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
