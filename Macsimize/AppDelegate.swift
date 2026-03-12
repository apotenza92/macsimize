import AppKit
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private lazy var settingsWindowController = SettingsWindowController(appState: appState)
    private var menuBarController: MenuBarController?
    private let openSettingsLaunchArguments: Set<String> = ["--settings", "-settings", "--open-settings"]
    private let openSettingsDistributedNotification = Notification.Name("pzc.Macsimize.openSettings")
    private var openSettingsObserver: NSObjectProtocol?
    private var updateManager: UpdateManager { appState.updateManager }
    private let isAutomatedTestSuite = ProcessInfo.processInfo.environment["MACSIMIZE_TEST_SUITE"] == "1"
    private var scheduledPermissionPrompts: [DispatchWorkItem] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        RuntimeLogger.log("Launched bundle at \(Bundle.main.bundleURL.path), bundleId \(Bundle.main.bundleIdentifier ?? "nil"), pid \(ProcessInfo.processInfo.processIdentifier), LSUIElement \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false)")

        startObservingOpenSettingsRequests()

        let launchRequestsSettings = ProcessInfo.processInfo.arguments.contains { openSettingsLaunchArguments.contains($0) }
        let finderLaunch = isFinderLaunch()
        let explicitSettingsRequest = launchRequestsSettings || finderLaunch

        // Finder-style relaunches are also used by restart/update flows.
        // Hand off only explicit settings launches to an already-running instance.
        let shouldRequestSettingsFromExisting = launchRequestsSettings

        if launchRequestsSettings {
            RuntimeLogger.log("Launch argument requested settings window")
        }
        if finderLaunch {
            RuntimeLogger.log("Finder launch detected")
        }

        if resolveRunningInstances(shouldRequestSettingsFromExisting: shouldRequestSettingsFromExisting) {
            return
        }

        bindSettings()
        updateMenuBarIconVisibility(isVisible: appState.settings.showMenuBarIcon)

        let firstLaunch = !appState.settings.firstLaunchCompleted
        let needsPermissions = !appState.permissions.state.allRequiredPermissionsGranted
        let shouldShowSettings = appState.settings.shouldShowSettingsOnLaunch(
            explicitSettingsRequest: explicitSettingsRequest,
            needsPermissions: needsPermissions
        )

        DispatchQueue.main.async {
            if shouldShowSettings {
                self.showSettingsWindow()
            }
            self.handlePermissionsIfNeeded(allowPrompt: shouldShowSettings)
            if firstLaunch {
                self.appState.settings.firstLaunchCompleted = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            self.updateManager.configureForLaunch(isAutomatedMode: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelScheduledPermissionPrompts()
        if let openSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(openSettingsObserver)
            self.openSettingsObserver = nil
        }
        appState.eventTapService.stop(reason: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        RuntimeLogger.log("Received app reopen request")
        showSettingsWindow()
        return false
    }

    func showSettingsWindow() {
        RuntimeLogger.log("Opening settings window")
        settingsWindowController.show()
    }

    func maximizeAllCurrentSpaceWindows() {
        RuntimeLogger.log("Menu bar requested batch maximize for current Space windows")
        appState.maximizeAllCurrentSpaceWindows()
    }

    func restoreAllCurrentSpaceWindows() {
        RuntimeLogger.log("Menu bar requested batch restore for current Space windows")
        appState.restoreAllCurrentSpaceWindows()
    }

    private func handlePermissionsIfNeeded(allowPrompt: Bool) {
        cancelScheduledPermissionPrompts()

        let permissionState = appState.permissions.state
        let needsAccessibility = !permissionState.accessibilityTrusted
        let needsInputMonitoring = !permissionState.inputMonitoringGranted
        guard needsAccessibility || needsInputMonitoring else { return }

        if isAutomatedTestSuite {
            appState.permissions.startMonitoringForChanges()
            return
        }

        appState.permissions.startMonitoringForChanges()

        guard allowPrompt else {
            return
        }

        schedulePermissionPrompts(
            needsAccessibility: needsAccessibility,
            needsInputMonitoring: needsInputMonitoring
        )
    }

    private func schedulePermissionPrompts(
        needsAccessibility: Bool,
        needsInputMonitoring: Bool
    ) {
        if needsAccessibility {
            let accessibilityPrompt = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !self.appState.permissions.state.accessibilityTrusted else { return }
                RuntimeLogger.log("Prompting for Accessibility permission after launch delay")
                self.appState.requestAccessibilityPermission()
            }
            scheduledPermissionPrompts.append(accessibilityPrompt)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: accessibilityPrompt)
        }

        if needsInputMonitoring {
            let inputMonitoringPrompt = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !self.appState.permissions.state.inputMonitoringGranted else { return }
                RuntimeLogger.log("Prompting for Input Monitoring permission after launch delay")
                self.appState.requestInputMonitoringPermission()
            }
            scheduledPermissionPrompts.append(inputMonitoringPrompt)
            let delay: TimeInterval = needsAccessibility ? 3.5 : 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: inputMonitoringPrompt)
        }
    }

    private func cancelScheduledPermissionPrompts() {
        for workItem in scheduledPermissionPrompts {
            workItem.cancel()
        }
        scheduledPermissionPrompts.removeAll()
    }

    private func isFinderLaunch() -> Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-psn_") }
    }

    @discardableResult
    private func resolveRunningInstances(shouldRequestSettingsFromExisting: Bool) -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return false
        }

        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != me }

        guard !others.isEmpty else {
            return false
        }

        if shouldRequestSettingsFromExisting {
            RuntimeLogger.log("Existing instance detected (\(others.map { $0.processIdentifier })); requesting settings window from the running app")
            requestSettingsOpenFromExistingInstance()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            NSApp.terminate(nil)
            return true
        }

        RuntimeLogger.log("Terminating other running instances: \(others.map { $0.processIdentifier })")

        for app in others {
            if !app.terminate() {
                _ = app.forceTerminate()
            }
        }

        let survivorsAfterTerminate = waitForOtherInstancesToExit(bundleId: bundleId)
        if !survivorsAfterTerminate.isEmpty {
            RuntimeLogger.log("Escalating termination for lingering instances: \(survivorsAfterTerminate.map { $0.processIdentifier })")
            for app in survivorsAfterTerminate {
                _ = app.forceTerminate()
                _ = kill(app.processIdentifier, SIGKILL)
            }
        }

        let survivorsAfterKill = waitForOtherInstancesToExit(bundleId: bundleId)
        if !survivorsAfterKill.isEmpty {
            RuntimeLogger.log("Aborting launch because old instances are still alive: \(survivorsAfterKill.map { $0.processIdentifier })")
            NSApp.terminate(nil)
            return true
        }

        return false
    }

    private func waitForOtherInstancesToExit(bundleId: String, timeout: TimeInterval = 1.5) -> [NSRunningApplication] {
        let deadline = Date().addingTimeInterval(timeout)
        var remaining = otherRunningInstances(bundleId: bundleId)

        while !remaining.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            remaining = otherRunningInstances(bundleId: bundleId)
        }

        return remaining
    }

    private func otherRunningInstances(bundleId: String) -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
    }

    private func bindSettings() {
        appState.settings.$showMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.updateMenuBarIconVisibility(isVisible: isVisible)
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarIconVisibility(isVisible: Bool) {
        if isVisible {
            if menuBarController == nil {
                menuBarController = MenuBarController(appDelegate: self)
            }
        } else {
            menuBarController?.invalidate()
            menuBarController = nil
        }
    }

    private func startObservingOpenSettingsRequests() {
        guard openSettingsObserver == nil else {
            return
        }

        let center = DistributedNotificationCenter.default()
        let observedObject = Bundle.main.bundleIdentifier
        openSettingsObserver = center.addObserver(
            forName: openSettingsDistributedNotification,
            object: observedObject,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                RuntimeLogger.log("Received distributed settings-open request")
                self.showSettingsWindow()
            }
        }
    }

    private func requestSettingsOpenFromExistingInstance() {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            openSettingsDistributedNotification,
            object: bundleId,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
