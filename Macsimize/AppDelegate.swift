import AppKit
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private lazy var settingsWindowController = SettingsWindowController(appState: appState)
    private var menuBarController: MenuBarController?
    private let automaticTerminationReason = "Macsimize keeps global interception active while running headless"
    private let openSettingsLaunchArguments: Set<String> = ["--settings", "-settings", "--open-settings"]
    private let maxAutomaticRelaunchAttempts = 2
    private let openSettingsDistributedNotification = Notification.Name("pzc.Macsimize.openSettings")
    private var openSettingsObserver: NSObjectProtocol?
    private var updateManager: UpdateManager { appState.updateManager }
    private let isAutomatedTestSuite = ProcessInfo.processInfo.environment["MACSIMIZE_TEST_SUITE"] == "1"
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(automaticTerminationReason)
        RuntimeLogger.log("Launched bundle at \(Bundle.main.bundleURL.path), bundleId \(Bundle.main.bundleIdentifier ?? "nil"), pid \(ProcessInfo.processInfo.processIdentifier), LSUIElement \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false)")

        startObservingOpenSettingsRequests()

        let launchRequestsSettings = ProcessInfo.processInfo.arguments.contains { openSettingsLaunchArguments.contains($0) }
        let finderLaunch = isFinderLaunch()
        let needsPermissions = !appState.permissions.state.allRequiredPermissionsGranted
        let launchDecision = LaunchBehavior.decide(
            LaunchBehaviorInput(
                isDevelopmentBuild: AppIdentity.runningIdentity == .development,
                onboardingCompleted: appState.settings.isOnboardingCompleted,
                showSettingsOnStartup: appState.settings.showSettingsOnStartup,
                launchArgumentsRequestSettings: launchRequestsSettings,
                launchedFromFinder: finderLaunch,
                needsPermissions: needsPermissions
            )
        )

        if launchRequestsSettings {
            RuntimeLogger.log("Launch argument requested settings window")
        }
        if finderLaunch {
            RuntimeLogger.log("Finder launch detected")
        }

        if resolveRunningInstances(shouldRequestSettingsFromExisting: launchDecision.shouldRequestSettingsFromExistingInstance) {
            return
        }

        bindSettings()
        updateMenuBarIconVisibility(isVisible: appState.settings.showMenuBarIcon)

        DispatchQueue.main.async {
            self.showInitialWindow(for: launchDecision.initialWindowRequest)
            self.handlePermissionsIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            self.updateManager.configureForLaunch(isAutomatedMode: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let openSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(openSettingsObserver)
            self.openSettingsObserver = nil
        }
        appState.eventTapService.stop(reason: nil)
        ProcessInfo.processInfo.enableAutomaticTermination(automaticTerminationReason)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        RuntimeLogger.log("Received app reopen request")
        showSettingsWindow()
        return false
    }

    func showSettingsWindow() {
        RuntimeLogger.log("Opening settings window")
        settingsWindowController.show(request: .settings(explicit: true))
    }

    func maximizeAllCurrentSpaceWindows() {
        RuntimeLogger.log("Menu bar requested batch maximize for current Space windows")
        appState.maximizeAllCurrentSpaceWindows()
    }

    func restoreAllCurrentSpaceWindows() {
        RuntimeLogger.log("Menu bar requested batch restore for current Space windows")
        appState.restoreAllCurrentSpaceWindows()
    }

    private func showInitialWindow(for request: InitialWindowRequest) {
        guard request != .none else {
            return
        }
        settingsWindowController.show(request: request)
    }

    private func handlePermissionsIfNeeded() {
        let permissionState = appState.permissions.state
        let needsAccessibility = !permissionState.accessibilityTrusted
        let needsInputMonitoring = !permissionState.inputMonitoringGranted
        guard needsAccessibility || needsInputMonitoring else { return }

        if isAutomatedTestSuite {
            appState.permissions.startMonitoringForChanges()
            return
        }

        RuntimeLogger.log("Permissions missing on launch; waiting for onboarding or settings actions before requesting them")
        appState.permissions.startMonitoringForChanges()
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
            let survivorPIDs = survivorsAfterKill.map(\.processIdentifier)
            let currentAttempt = RelaunchSupport.automaticRelaunchAttempt(arguments: ProcessInfo.processInfo.arguments)
            RuntimeLogger.log("Old instances still alive after cleanup attempt \(currentAttempt): \(survivorPIDs)")

            if scheduleAutomaticRelaunchIfPossible(currentAttempt: currentAttempt, survivorPIDs: survivorPIDs) {
                return true
            }

            RuntimeLogger.log("Aborting launch because old instances are still alive: \(survivorPIDs)")
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

    private func scheduleAutomaticRelaunchIfPossible(currentAttempt: Int, survivorPIDs: [pid_t]) -> Bool {
        guard currentAttempt < maxAutomaticRelaunchAttempts else {
            return false
        }

        let nextAttempt = currentAttempt + 1
        RuntimeLogger.log("Scheduling automatic relaunch attempt \(nextAttempt) after stale instances survived cleanup: \(survivorPIDs)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = RelaunchSupport.launchArguments(
            from: ProcessInfo.processInfo.arguments,
            openSettingsArguments: openSettingsLaunchArguments,
            nextAutomaticRelaunchAttempt: nextAttempt
        )

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                RuntimeLogger.log("Automatic relaunch attempt \(nextAttempt) failed: \(error.localizedDescription)")
                NSApp.terminate(nil)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        }

        return true
    }
}
