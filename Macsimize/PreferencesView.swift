import AppKit
import SwiftUI

struct PreferencesView: View {
    private enum SettingsDestination: Hashable, CaseIterable {
        case general
        case behavior
        case permissions
        case updates
        case about

        var title: String {
            switch self {
            case .general:
                AppStrings.generalSectionTitle
            case .behavior:
                AppStrings.behaviorSectionTitle
            case .permissions:
                AppStrings.permissionsSectionTitle
            case .updates:
                AppStrings.updatesSectionTitle
            case .about:
                "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                "gearshape"
            case .behavior:
                "macwindow"
            case .permissions:
                "hand.raised"
            case .updates:
                "arrow.triangle.2.circlepath"
            case .about:
                "info.circle"
            }
        }
    }

    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var updateManager: UpdateManager

    private let appState: AppState
    private let appDisplayName = AppIdentity.displayName
    private let contentDidChange: @MainActor () -> Void
    @State private var selectedDestination = SettingsDestination.general

    init(appState: AppState, contentDidChange: @escaping @MainActor () -> Void = {}) {
        self.appState = appState
        self.contentDidChange = contentDidChange
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _updateManager = ObservedObject(wrappedValue: appState.updateManager)
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                List(SettingsDestination.allCases, id: \.self, selection: $selectedDestination) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination)
                }
                .listStyle(.sidebar)
                .navigationTitle("Settings")
            } detail: {
                selectedContent
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    ForEach(SettingsDestination.allCases, id: \.self) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                    }
                }
                .padding()
                .fixedSize(horizontal: true, vertical: true)

                selectedContent
                    .fixedSize(horizontal: true, vertical: true)
            }
                .hidden()
                .accessibilityHidden(true)
        }
        .navigationSplitViewStyle(.balanced)
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: selectedDestination) {
            scheduleContentRefit()
        }
        .onChange(of: permissions.state) {
            scheduleContentRefit()
        }
        .onChange(of: updateManager.updateStatusMessage) {
            scheduleContentRefit()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedDestination {
        case .general:
            generalPage
        case .behavior:
            behaviorPage
        case .permissions:
            permissionsPage
        case .updates:
            updatesPage
        case .about:
            aboutPage
        }
    }

    private var generalPage: some View {
        SettingsPage(
            title: AppStrings.generalSectionTitle,
            subtitle: "Choose how \(appDisplayName) appears and starts."
        ) {
            SettingsSection(
                title: "Menu Bar",
                subtitle: "Keep \(appDisplayName) within easy reach."
            ) {
                Toggle(AppStrings.showMenuBarIcon, isOn: $settings.showMenuBarIcon)
            }

            Divider()

            SettingsSection(
                title: "Startup",
                subtitle: "Choose what happens when you sign in or open the app."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(AppStrings.showSettingsOnStartup, isOn: $settings.showSettingsOnStartup)
                    SharedLoginItemSection(settings: settings)
                }
            }
        }
    }

    private var behaviorPage: some View {
        SettingsPage(
            title: AppStrings.greenButtonBehaviorSectionTitle,
            subtitle: "Choose what happens when you click a window’s green button."
        ) {
            Picker(AppStrings.greenButtonClickLabel, selection: selectedActionBinding) {
                ForEach(WindowActionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text(settings.selectedAction.helpText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionsPage: some View {
        SettingsPage(
            title: AppStrings.permissionsSectionTitle,
            subtitle: "Manage the macOS access \(appDisplayName) needs to control windows."
        ) {
            RequiredPermissionsList(appState: appState)

            if let footerText {
                Text(footerText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updatesPage: some View {
        SettingsPage(
            title: AppStrings.updatesSectionTitle,
            subtitle: "Keep \(appDisplayName) current and choose how often to check."
        ) {
            SharedUpdatesSection(
                settings: settings,
                updateManager: updateManager
            )
        }
    }

    private var aboutPage: some View {
        SettingsPage(
            title: "About \(appDisplayName)",
            subtitle: AppStrings.currentVersionStatusMessage
        ) {
            SettingsSection(
                title: "Information and Support",
                subtitle: "Learn more about \(appDisplayName) or visit the project."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("About \(appDisplayName)") {
                        appState.showAboutPanel()
                    }

                    Button("View on GitHub") {
                        openGitHubPage()
                    }
                    .help(AppStrings.openGitHubHelp(appName: appDisplayName))
                }
            }

            Divider()

            SettingsSection(
                title: "App Controls",
                subtitle: "Restart the app to reload its services, or quit completely."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Button(AppStrings.restartButtonTitle) {
                        appState.restartApp()
                    }

                    Button(AppStrings.quitButtonTitle) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private var selectedActionBinding: Binding<WindowActionMode> {
        Binding(
            get: { settings.selectedAction },
            set: { appState.setSelectedAction($0) }
        )
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

    private func openGitHubPage() {
        guard let url = URL(string: "https://github.com/apotenza92/macsimize") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func scheduleContentRefit() {
        DispatchQueue.main.async {
            contentDidChange()
        }
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding(28)
            .fixedSize(horizontal: true, vertical: true)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(.vertical, 20)
    }
}

struct SettingsInfoRow: View {
    private let icon: Image?
    let title: String
    let detail: String

    init(systemImage: String, title: String, detail: String) {
        self.icon = Image(systemName: systemImage)
        self.title = title
        self.detail = detail
    }

    init(title: String, detail: String) {
        self.icon = nil
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let icon {
                Label {
                    Text(title)
                } icon: {
                    icon
                        .renderingMode(.template)
                }
                .font(.headline)
            } else {
                Text(title)
                    .font(.headline)
            }

            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

struct SharedLoginItemSection: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if AppIdentity.supportsLoginItem {
                Toggle(AppStrings.startAtLogin(appName: AppIdentity.displayName), isOn: $settings.startAtLogin)
            } else {
                Label("Start at Login is unavailable in development builds.", systemImage: "hammer")
                    .foregroundStyle(.secondary)
            }

            Text("Launch \(AppIdentity.displayName) automatically when you sign in to your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct SharedUpdatesSection: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if AppIdentity.supportsUpdates {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.checkFrequencyLabel)
                        .font(.headline)

                    Picker(AppStrings.checkFrequencyLabel, selection: $settings.updateCheckFrequency) {
                        ForEach(UpdateCheckFrequency.allCases) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .labelsHidden()

                    Text("Automatic checks run quietly according to the frequency you choose.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

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
            } else {
                Label(
                    updateManager.updateStatusMessage ?? AppStrings.updatesDisabledDevelopmentBuild,
                    systemImage: "hammer"
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionAccessRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusIcon
                Text(title)
                    .font(.headline)
                Spacer()
                    statusText
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(AppStrings.openSettingsButtonTitle, action: action)
        }
    }

    private var statusIcon: some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.title2)
            .foregroundStyle(granted ? .green : .orange)
    }

    private var statusText: some View {
        Text(granted ? "Enabled" : "Required")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(granted ? .green : .secondary)
    }
}

struct RequiredPermissionsList: View {
    @ObservedObject private var permissions: PermissionsCoordinator
    private let appState: AppState
    init(appState: AppState) {
        self.appState = appState
        _permissions = ObservedObject(wrappedValue: appState.permissions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionAccessRow(
                title: AppStrings.accessibilityButtonTitle,
                detail: AppStrings.permissionAccessibilityWhyNeeded,
                granted: permissions.state.accessibilityTrusted,
                action: appState.openAccessibilitySettings
            )

            Divider()

            PermissionAccessRow(
                title: AppStrings.inputMonitoringButtonTitle,
                detail: AppStrings.permissionInputMonitoringWhyNeeded,
                granted: permissions.state.inputMonitoringGranted,
                action: appState.openInputMonitoringSettings
            )
        }
    }
}
