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
    private let appDisplayName = AppIdentity.displayName

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
            Text(AppStrings.generalSectionTitle)
                .font(sectionTitleFont)

            checkboxRow(AppStrings.showSettingsOnStartup, isOn: $settings.showSettingsOnStartup)
            checkboxRow(AppStrings.startAtLogin(appName: appDisplayName), isOn: $settings.startAtLogin)

            HStack(spacing: 12) {
                Button(AppStrings.restartButtonTitle) {
                    appState.restartApp()
                }
                .buttonStyle(.bordered)

                Button(AppStrings.quitButtonTitle) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)

                Button(AppStrings.aboutButtonTitle) {
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
                .help(AppStrings.openGitHubHelp(appName: appDisplayName))
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.permissionsSectionTitle)
                .font(sectionTitleFont)

            if permissions.state.hasVisibleIssue {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(permissions.state.summary)
                            .font(.system(size: 13, weight: .semibold))
                        Text(statusDetailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.1))
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                permissionActionButton(
                    title: AppStrings.accessibilityButtonTitle,
                    granted: permissions.state.accessibilityTrusted,
                    action: appState.openAccessibilitySettings
                )
                permissionActionButton(
                    title: AppStrings.inputMonitoringButtonTitle,
                    granted: permissions.state.inputMonitoringGranted,
                    action: appState.openInputMonitoringSettings
                )
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.updatesSectionTitle)
                .font(sectionTitleFont)

            HStack(alignment: .center, spacing: 12) {
                Button(AppStrings.checkForUpdatesButtonTitle, action: updateManager.checkForUpdates)
                    .buttonStyle(.borderedProminent)
                    .disabled(!updateManager.canCheckForUpdates)

                Picker(AppStrings.checkFrequencyLabel, selection: $settings.updateCheckFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
            }

            if let updateStatusMessage = updateManager.updateStatusMessage {
                Text(updateStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.behaviorSectionTitle)
                .font(sectionTitleFont)

            Text(AppStrings.greenButtonClickLabel)
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
            if !granted {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .frame(width: 14)
            }
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

    private var statusDetailText: String {
        var detail = permissions.state.detail
        if settings.selectedAction == .maximize && !permissions.state.eventTapRunning {
            detail += " \(AppStrings.inactiveInterceptionWarning)"
        }
        return detail
    }
}
