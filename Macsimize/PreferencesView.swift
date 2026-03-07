import AppKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var permissions: PermissionsCoordinator
    @ObservedObject private var diagnostics: DebugDiagnostics
    @ObservedObject private var eventTapService: EventTapService

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        _settings = ObservedObject(wrappedValue: appState.settings)
        _permissions = ObservedObject(wrappedValue: appState.permissions)
        _diagnostics = ObservedObject(wrappedValue: appState.diagnostics)
        _eventTapService = ObservedObject(wrappedValue: appState.eventTapService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topRow
            bottomRow
            footerRow
        }
        .padding(16)
        .frame(width: 760, height: 560, alignment: .topLeading)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 16) {
            generalCard
                .frame(width: 232, alignment: .topLeading)
            behaviorCard
                .frame(width: 232, alignment: .topLeading)
            statusCard
                .frame(width: 232, alignment: .topLeading)
        }
    }

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 16) {
            permissionsCard
                .frame(width: 290, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 16) {
                exclusionsCard
                diagnosticsCard
            }
            .frame(width: 422, alignment: .topLeading)
        }
    }

    private var footerRow: some View {
        HStack {
            Spacer()
            Button("Quit Macsimize") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private var generalCard: some View {
        settingsCard(title: "General") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show settings on startup", isOn: $settings.showSettingsOnStartup)
                    .toggleStyle(.checkbox)

                Divider()

                Button("About Macsimize") {
                    appState.showAboutPanel()
                }
                .buttonStyle(.bordered)

                Button("Restart App") {
                    appState.restartApp()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var behaviorCard: some View {
        settingsCard(title: "Behavior") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Green button click")
                    .font(.subheadline.weight(.medium))

                Picker("Green button click", selection: $settings.selectedAction) {
                    ForEach(WindowActionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(settings.selectedAction.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text(settings.selectedAction == .maximize
                     ? "Maximize expands to the usable screen area and restores on the next clean click."
                     : "Full Screen leaves the green button untouched so macOS handles native full screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusCard: some View {
        settingsCard(title: "Status") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    eventTapService.isRunning ? "Interception Running" : "Interception Idle",
                    systemImage: eventTapService.isRunning ? "checkmark.circle.fill" : "pause.circle"
                )
                .foregroundStyle(eventTapService.isRunning ? .green : .secondary)

                Text(permissions.state.summary)
                    .font(.subheadline.weight(.medium))

                Text(permissions.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(spacing: 8) {
                    Button("Refresh") {
                        appState.refreshPermissions(promptIfNeeded: false)
                    }
                    .buttonStyle(.bordered)

                    Button("Restart Tap") {
                        appState.restartEventTap()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var permissionsCard: some View {
        settingsCard(title: "Permissions") {
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Accessibility",
                    granted: permissions.state.accessibilityTrusted,
                    description: "Needed to identify the green button and resize windows.",
                    actionTitle: "Open Accessibility"
                ) {
                    appState.openAccessibilitySettings()
                }

                Divider()

                permissionRow(
                    title: "Input Monitoring",
                    granted: permissions.state.inputMonitoringGranted,
                    description: "Needed for the global click tap to start reliably.",
                    actionTitle: "Open Input Monitoring"
                ) {
                    appState.openInputMonitoringSettings()
                }

                Divider()

                permissionRow(
                    title: "Secure Event Input",
                    granted: !permissions.state.secureEventInputEnabled,
                    description: "If another app holds secure input, interception can be temporarily limited.",
                    actionTitle: "Refresh"
                ) {
                    appState.refreshPermissions(promptIfNeeded: false)
                }
            }
        }
    }

    private var exclusionsCard: some View {
        settingsCard(title: "Excluded Apps") {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    "com.apple.finder, com.apple.dt.Xcode",
                    text: Binding(
                        get: { settings.excludedBundleIDsText },
                        set: { settings.excludedBundleIDsText = $0 }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

                HStack {
                    Button("Exclude Frontmost App") {
                        appState.addFrontmostAppToExclusions()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("\(settings.excludedBundleIDs.count) excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        settingsCard(title: "Diagnostics") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable diagnostics", isOn: $settings.diagnosticsEnabled)
                    .toggleStyle(.checkbox)

                HStack(spacing: 8) {
                    Button("Snapshot Frontmost Window") {
                        appState.captureDiagnosticsSnapshot()
                    }
                    .buttonStyle(.bordered)

                    Button("Clear Logs") {
                        diagnostics.clear()
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if diagnostics.entries.isEmpty {
                            Text("No recent diagnostic entries.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(diagnostics.entries.prefix(8)) { entry in
                                Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.message)")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        description: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
