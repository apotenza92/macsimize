import AppKit
import SwiftUI

enum SettingsLayout {
    static let detailWidth: CGFloat = 508
    static let defaultSettingsHeight: CGFloat = 640
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let controlSpacing: CGFloat = 12
    static let textSpacing: CGFloat = 4
}

struct PreferencesView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var updateManager: UpdateManager
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _updateManager = ObservedObject(wrappedValue: appState.updateManager)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SettingsSection(title: AppStrings.greenButtonBehaviorSectionTitle) {
                    Picker(AppStrings.greenButtonClickLabel, selection: selectedActionBinding) {
                        ForEach(WindowActionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()

                    Text(settings.selectedAction.helpText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                SettingsSection(title: "Menu Bar and Startup") {
                    HStack(spacing: SettingsLayout.controlSpacing) {
                        Toggle(AppStrings.showMenuBarIcon, isOn: $settings.showMenuBarIcon)
                        Toggle(AppStrings.showSettingsOnStartup, isOn: $settings.showSettingsOnStartup)
                    }
                    if AppIdentity.supportsLoginItem {
                        Toggle(AppStrings.startAtLogin(appName: AppIdentity.displayName), isOn: $settings.startAtLogin)
                    }
                }

                Divider()

                SettingsSection(title: AppStrings.permissionsSectionTitle) {
                    RequiredPermissionsList(appState: appState)
                    if permissions.state.secureEventInputEnabled {
                        Text(AppStrings.permissionDetailSecureEventInput)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                SettingsSection(title: AppStrings.updatesSectionTitle) {
                    SharedUpdatesSection(settings: settings, updateManager: updateManager)
                }

                Divider()

                VStack(alignment: .leading, spacing: SettingsLayout.controlSpacing) {
                    Text("\(AppIdentity.displayName) · \(AppStrings.currentVersionStatusMessage)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: SettingsLayout.controlSpacing) {
                        Button("About") { appState.showAboutPanel() }
                        Button("GitHub") { openGitHubPage() }
                            .help(AppStrings.openGitHubHelp(appName: AppIdentity.displayName))
                        Spacer()
                        Button(AppStrings.restartButtonTitle) { appState.restartApp() }
                        Button(AppStrings.quitButtonTitle) { NSApp.terminate(nil) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SettingsLayout.verticalPadding)
            .reportSettingsContentHeight()
        }
        .frame(width: SettingsLayout.detailWidth)
        .frame(minHeight: 180, idealHeight: SettingsLayout.defaultSettingsHeight, maxHeight: .infinity)
    }

    private var selectedActionBinding: Binding<WindowActionMode> {
        Binding(
            get: { settings.selectedAction },
            set: { appState.setSelectedAction($0) }
        )
    }

    private func openGitHubPage() {
        guard let url = URL(string: "https://github.com/apotenza92/macsimize") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SettingsPage<Content: View>: View {
    let width: CGFloat
    let title: String
    let subtitle: String
    let titleIcon: Image?
    @ViewBuilder let content: Content

    init(
        width: CGFloat = SettingsLayout.detailWidth,
        title: String,
        subtitle: String,
        titleIcon: Image? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.width = width
        self.title = title
        self.subtitle = subtitle
        self.titleIcon = titleIcon
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                VStack(spacing: SettingsLayout.controlSpacing) {
                    if let titleIcon {
                        titleIcon
                            .renderingMode(.template)
                            .accessibilityLabel("Macsimize menu bar icon")
                            .help("Look for this icon in the menu bar.")
                    }
                    VStack(spacing: SettingsLayout.textSpacing) {
                        Text(title)
                            .font(.title2.weight(.semibold))
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsLayout.horizontalPadding)
            .padding(.vertical, SettingsLayout.verticalPadding)
            .reportSettingsContentHeight()
        }
        .frame(width: width)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String = "",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.controlSpacing) {
            VStack(alignment: .leading, spacing: SettingsLayout.textSpacing) {
                Text(title)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
    }
}

struct SharedUpdatesSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.controlSpacing) {
            if AppIdentity.supportsUpdates {
                Picker(AppStrings.checkFrequencyLabel, selection: $settings.updateCheckFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                Button(
                    updateManager.hasAvailableUpdate
                        ? AppStrings.installUpdateButtonTitle
                        : AppStrings.checkForUpdatesButtonTitle,
                    action: updateManager.checkForUpdates
                )
                .disabled(!updateManager.canCheckForUpdates || updateManager.isCheckingForUpdates)

                Text(updateManager.updateStatusMessage ?? AppStrings.currentVersionStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(
                    updateManager.updateStatusMessage ?? AppStrings.updatesDisabledDevelopmentBuild,
                    systemImage: "hammer"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PermissionAccessRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    var detailFont: Font = .subheadline

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayout.controlSpacing) {
            statusIcon

            VStack(alignment: .leading, spacing: SettingsLayout.textSpacing) {
                Text(title)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(AppStrings.openSettingsButtonTitle, action: action)
                .fixedSize()
        }
    }

    private var statusIcon: some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.body)
            .foregroundStyle(granted ? .green : .orange)
            .accessibilityLabel(granted ? "Permission enabled" : "Permission not enabled")
    }

}

struct RequiredPermissionsList: View {
    @ObservedObject private var permissions: PermissionsCoordinator
    private let appState: AppState
    private let detailFont: Font

    init(appState: AppState, detailFont: Font = .subheadline) {
        self.appState = appState
        self.detailFont = detailFont
        _permissions = ObservedObject(wrappedValue: appState.permissions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.controlSpacing) {
            PermissionAccessRow(
                title: AppStrings.accessibilityButtonTitle,
                detail: AppStrings.permissionAccessibilityWhyNeeded,
                granted: permissions.state.accessibilityTrusted,
                action: appState.openAccessibilitySettings,
                detailFont: detailFont
            )

            PermissionAccessRow(
                title: AppStrings.inputMonitoringButtonTitle,
                detail: AppStrings.permissionInputMonitoringWhyNeeded,
                granted: permissions.state.inputMonitoringGranted,
                action: appState.openInputMonitoringSettings,
                detailFont: detailFont
            )
        }
    }
}
