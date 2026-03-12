import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var updateManager: UpdateManager

    private let appState: AppState
    private let appDisplayName = AppIdentity.displayName
    private let contentWidth: CGFloat = 360
    private let sectionSpacing: CGFloat = 24
    private let rowSpacing: CGFloat = 12
    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _updateManager = ObservedObject(wrappedValue: appState.updateManager)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                generalSection
                Divider()
                behaviorSection
                Divider()
                updatesSection
                Divider()
                permissionsSection
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(width: contentWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var generalSection: some View {
        settingsSection(AppStrings.generalSectionTitle) {
            Toggle(AppStrings.showMenuBarIcon, isOn: $settings.showMenuBarIcon)
            Toggle(AppStrings.showSettingsOnStartup, isOn: $settings.showSettingsOnStartup)
            Toggle(AppStrings.startAtLogin(appName: appDisplayName), isOn: $settings.startAtLogin)

            HStack(spacing: 8) {
                Button(AppStrings.restartButtonTitle) {
                    appState.restartApp()
                }

                Button(AppStrings.quitButtonTitle) {
                    NSApp.terminate(nil)
                }

                Button(AppStrings.aboutButtonTitle) {
                    appState.showAboutPanel()
                }

                Button("GitHub") {
                    openGitHubPage()
                }
                .help(AppStrings.openGitHubHelp(appName: appDisplayName))
            }
        }
    }

    private var permissionsSection: some View {
        settingsSection(AppStrings.permissionsSectionTitle) {
            if permissions.state.hasVisibleIssue {
                VStack(alignment: .leading, spacing: 6) {
                    Label(permissions.state.summary, systemImage: "exclamationmark.triangle.fill")
                    Text(statusDetailText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            permissionActionButton(
                title: AppStrings.accessibilityButtonTitle,
                description: AppStrings.permissionAccessibilityWhyNeeded,
                granted: permissions.state.accessibilityTrusted,
                action: appState.openAccessibilitySettings
            )
            permissionActionButton(
                title: AppStrings.inputMonitoringButtonTitle,
                description: AppStrings.permissionInputMonitoringWhyNeeded,
                granted: permissions.state.inputMonitoringGranted,
                action: appState.openInputMonitoringSettings
            )
        }
    }

    private var updatesSection: some View {
        settingsSection(AppStrings.updatesSectionTitle) {
            HStack(alignment: .center, spacing: 12) {
                Button(
                    updateManager.hasAvailableUpdate
                        ? AppStrings.installUpdateButtonTitle
                        : AppStrings.checkForUpdatesButtonTitle,
                    action: updateManager.checkForUpdates
                )
                .disabled(!updateManager.canCheckForUpdates || updateManager.isCheckingForUpdates)
                .fixedSize()

                Spacer(minLength: 0)

                Text(AppStrings.checkFrequencyCompactLabel)
                    .foregroundStyle(.secondary)

                Picker("", selection: $settings.updateCheckFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .labelsHidden()
                .frame(width: 104, alignment: .leading)
            }

            Text(updateManager.updateStatusMessage ?? AppStrings.currentVersionStatusMessage)
                .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var behaviorSection: some View {
        settingsSection(AppStrings.behaviorSectionTitle) {
            LabeledContent(AppStrings.greenButtonClickLabel) {
                Picker("", selection: selectedActionBinding) {
                    ForEach(WindowActionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160, alignment: .leading)
            }

            Text(settings.selectedAction.helpText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedActionBinding: Binding<WindowActionMode> {
        Binding(
            get: { settings.selectedAction },
            set: { appState.setSelectedAction($0) }
        )
    }

    private func permissionActionButton(
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(title, action: action)
                permissionStatusBadge(granted: granted)
            }

            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionStatusBadge(granted: Bool) -> some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(granted ? .green : .orange)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.vertical, sectionSpacing / 2)
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
