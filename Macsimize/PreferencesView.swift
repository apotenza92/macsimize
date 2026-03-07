import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator

    private let appState: AppState
    private let horizontalPadding: CGFloat = 16
    private let contentFont: Font = .system(size: 14)
    private let sectionTitleFont: Font = .system(size: 14, weight: .semibold)

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            generalSection
            behaviorSection
            permissionsSection
        }
        .font(contentFont)
        .padding(horizontalPadding)
        .frame(width: 380, height: 332, alignment: .topLeading)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
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
                permissionActionButton(
                    title: "Secure Event Input",
                    granted: !permissions.state.secureEventInputEnabled,
                    action: { appState.refreshPermissions(promptIfNeeded: false) }
                )
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Behaviour")
                .font(sectionTitleFont)

            Text("Green button click")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: $settings.selectedAction) {
                ForEach(WindowActionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
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

    private func openGitHubPage() {
        guard let url = URL(string: "https://github.com/apotenza92/macsimize") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
