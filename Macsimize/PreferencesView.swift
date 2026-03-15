import AppKit
import SwiftUI

enum SharedUpdatesSectionStyle {
    case settings
    case onboarding
}

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
            SharedLoginItemSection(settings: settings)

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
            SharedPermissionsSection(appState: appState)
        }
    }

    private var updatesSection: some View {
        settingsSection(AppStrings.updatesSectionTitle) {
            SharedUpdatesSection(settings: settings, updateManager: updateManager, style: .settings)
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
}

struct SharedLoginItemSection: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        if AppIdentity.supportsLoginItem {
            Toggle(AppStrings.startAtLogin(appName: AppIdentity.displayName), isOn: $settings.startAtLogin)
        } else {
            Text("Start at Login is unavailable in development builds.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SharedUpdatesSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateManager: UpdateManager
    let style: SharedUpdatesSectionStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if AppIdentity.supportsUpdates {
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
                    .frame(width: style == .settings ? 104 : 132, alignment: .leading)
                }
            } else {
                Text(updateManager.updateStatusMessage ?? AppStrings.updatesDisabledDevelopmentBuild)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(updateManager.updateStatusMessage ?? AppStrings.currentVersionStatusMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SharedPermissionsSection: View {
    @ObservedObject private var permissions: PermissionsCoordinator

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        _permissions = ObservedObject(wrappedValue: appState.permissions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionRow(
                title: AppStrings.accessibilityButtonTitle,
                infoText: AppStrings.permissionAccessibilityWhyNeeded,
                granted: permissions.state.accessibilityTrusted,
                action: appState.openAccessibilitySettings
            )

            permissionRow(
                title: AppStrings.inputMonitoringButtonTitle,
                infoText: AppStrings.permissionInputMonitoringWhyNeeded,
                granted: permissions.state.inputMonitoringGranted,
                action: appState.openInputMonitoringSettings
            )

            if let footerText {
                Text(footerText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(
        title: String,
        infoText: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? Color.green : Color.orange)

                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(infoText)
            }

            Spacer(minLength: 0)

            Button(AppStrings.openSettingsButtonTitle, action: action)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerText: String? {
        if permissions.state.allRequiredPermissionsGranted {
            return "All required permissions are enabled."
        }

        if permissions.state.secureEventInputEnabled {
            return AppStrings.permissionDetailSecureEventInput
        }

        return nil
    }
}
