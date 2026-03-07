import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private lazy var settingsWindowController = SettingsWindowController(appState: appState)
    private var menuBarController: MenuBarController?
    private let openSettingsLaunchArguments: Set<String> = ["--settings", "-settings", "--open-settings"]
    private let openSettingsDistributedNotification = Notification.Name("pzc.Macsimize.openSettings")
    private var openSettingsObserver: NSObjectProtocol?
    private var updateManager: UpdateManager { appState.updateManager }

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

        menuBarController = MenuBarController(appDelegate: self)
        updateManager.configureForLaunch(isAutomatedMode: false)

        let firstLaunch = !appState.settings.firstLaunchCompleted
        let shouldShowSettings = firstLaunch || explicitSettingsRequest || appState.settings.showSettingsOnStartup

        DispatchQueue.main.async {
            if shouldShowSettings {
                self.showSettingsWindow()
            }
            self.handlePermissionsIfNeeded(allowPrompt: shouldShowSettings)
            if firstLaunch {
                self.appState.settings.firstLaunchCompleted = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    private func handlePermissionsIfNeeded(allowPrompt: Bool) {
        let permissionState = appState.permissions.state
        let needsAccessibility = !permissionState.accessibilityTrusted
        let needsInputMonitoring = !permissionState.inputMonitoringGranted
        guard needsAccessibility || needsInputMonitoring else { return }

        if allowPrompt && needsAccessibility {
            appState.requestAccessibilityPermission()
        }

        if allowPrompt && needsInputMonitoring {
            let delay: TimeInterval = needsAccessibility ? 0.6 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.appState.requestInputMonitoringPermission()
            }
        } else {
            appState.permissions.startMonitoringForChanges()
        }
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
            NSApp.terminate(nil)
            return true
        }

        RuntimeLogger.log("Terminating other running instances: \(others.map { $0.processIdentifier })")

        for app in others {
            if !app.terminate() {
                _ = app.forceTerminate()
            }
        }

        return false
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
