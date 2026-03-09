import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let settings: SettingsStore
    let permissions: PermissionsCoordinator
    let diagnostics: DebugDiagnostics
    let updateManager: UpdateManager
    let accessibilityService: AccessibilityService
    let frameStore: WindowFrameStore
    let maximizeStrategy: MaximizeStrategy
    let actionEngine: WindowActionEngine
    let eventTapService: EventTapService

    private var cancellables = Set<AnyCancellable>()

    init(userDefaults: UserDefaults = .standard) {
        settings = SettingsStore(userDefaults: userDefaults)
        permissions = PermissionsCoordinator()
        diagnostics = DebugDiagnostics()
        updateManager = UpdateManager(settings: settings)
        accessibilityService = AccessibilityService(diagnostics: diagnostics)
        frameStore = WindowFrameStore()
        maximizeStrategy = MaximizeStrategy(frameStore: frameStore, diagnostics: diagnostics)
        actionEngine = WindowActionEngine(
            maximizeStrategy: maximizeStrategy,
            diagnostics: diagnostics
        )
        eventTapService = EventTapService(
            settings: settings,
            permissions: permissions,
            accessibilityService: accessibilityService,
            actionEngine: actionEngine,
            diagnostics: diagnostics
        )

        diagnostics.setEnabledProvider { [weak settings] in
            settings?.diagnosticsEnabled ?? false
        }

        refreshPermissions(promptIfNeeded: false)
        bind()
    }

    func refreshPermissions(promptIfNeeded: Bool) {
        permissions.refresh(promptIfNeeded: promptIfNeeded)
        syncPermissionDrivenServices()
    }

    func requestAccessibilityPermission() {
        permissions.refresh(promptIfNeeded: true)
        syncPermissionDrivenServices()
    }

    func requestInputMonitoringPermission() {
        permissions.requestInputMonitoringPermission()
        syncPermissionDrivenServices()
    }

    func restartEventTap() {
        eventTapService.restart()
    }

    func captureDiagnosticsSnapshot() {
        accessibilityService.captureFrontmostWindowSnapshot()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        requestAccessibilityPermission()
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        requestInputMonitoringPermission()
    }

    func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]

        do {
            try task.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        } catch {
            diagnostics.logMessage("Failed to relaunch app: \(error.localizedDescription)", forceVisible: true)
        }
    }

    private func bind() {
        settings.$selectedAction
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] selectedAction in
                self?.refreshLiveInterceptionConfiguration(selectedAction: selectedAction)
            }
            .store(in: &cancellables)

        settings.$diagnosticsEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] diagnosticsEnabled in
                self?.refreshLiveInterceptionConfiguration(diagnosticsEnabled: diagnosticsEnabled)
            }
            .store(in: &cancellables)

        permissions.$state
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                self?.syncPermissionDrivenServices(for: state)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(eventTapService.$isRunning, eventTapService.$lastFailureReason)
            .sink { [weak self] isRunning, lastFailureReason in
                self?.permissions.updateEventTapStatus(isRunning: isRunning, lastFailureReason: lastFailureReason)
            }
            .store(in: &cancellables)
    }

    private func refreshLiveInterceptionConfiguration(
        selectedAction: WindowActionMode? = nil,
        diagnosticsEnabled: Bool? = nil
    ) {
        if permissions.state.allRequiredPermissionsGranted {
            eventTapService.startIfPossible(
                selectedAction: selectedAction,
                diagnosticsEnabled: diagnosticsEnabled
            )
        } else {
            eventTapService.refreshConfiguration(
                selectedAction: selectedAction,
                diagnosticsEnabled: diagnosticsEnabled
            )
        }
    }

    private func syncPermissionDrivenServices() {
        syncPermissionDrivenServices(for: permissions.state)
    }

    private func syncPermissionDrivenServices(for state: PermissionState) {
        if state.allRequiredPermissionsGranted {
            permissions.stopMonitoringForChanges()
            eventTapService.startIfPossible()
        } else {
            permissions.startMonitoringForChanges()
            eventTapService.stop(reason: state.detail)
        }
    }
}
