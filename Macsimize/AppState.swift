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

        bind()
        refreshPermissions(promptIfNeeded: false)
    }

    func refreshPermissions(promptIfNeeded: Bool) {
        permissions.refresh(promptIfNeeded: promptIfNeeded)
        permissions.startMonitoringForChanges()
        eventTapService.startIfPossible()
    }

    func requestAccessibilityPermission() {
        permissions.refresh(promptIfNeeded: true)
        permissions.startMonitoringForChanges()
        eventTapService.startIfPossible()
    }

    func requestInputMonitoringPermission() {
        permissions.requestInputMonitoringPermission()
        permissions.startMonitoringForChanges()
        eventTapService.startIfPossible()
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
        Publishers.CombineLatest(
            settings.$selectedAction.removeDuplicates(),
            settings.$diagnosticsEnabled.removeDuplicates()
        )
        .sink { [weak self] _, _ in
            self?.eventTapService.refreshConfiguration()
            self?.eventTapService.startIfPossible()
        }
        .store(in: &cancellables)

        permissions.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else {
                    return
                }
                if state.allRequiredPermissionsGranted {
                    self.permissions.stopMonitoringForChanges()
                    self.eventTapService.startIfPossible()
                } else {
                    self.permissions.startMonitoringForChanges()
                    self.eventTapService.stop(reason: state.detail)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(eventTapService.$isRunning, eventTapService.$lastFailureReason)
            .sink { [weak self] isRunning, lastFailureReason in
                self?.permissions.updateEventTapStatus(isRunning: isRunning, lastFailureReason: lastFailureReason)
            }
            .store(in: &cancellables)
    }
}
