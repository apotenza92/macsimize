import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject, @preconcurrency SPUUpdaterDelegate {
    nonisolated private enum SparkleErrorCode {
        static let noUpdate = 1001
        static let installationCanceled = 4007
        static let installationAuthorizeLater = 4008
    }

    nonisolated private enum Timing {
        static let manualCheckStatusTimeoutNanoseconds: UInt64 = 12_000_000_000
    }

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateStatusMessage: String?

    var hasAvailableUpdate: Bool {
        Self.hasAvailableUpdateStatusMessage(updateStatusMessage)
    }

    private let settings: SettingsStore
    private let diagnostics: DebugDiagnostics
    private var updateCheckTimer: Timer?
    private var manualCheckStatusTimeoutTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var didConfigure = false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(settings: SettingsStore, diagnostics: DebugDiagnostics) {
        self.settings = settings
        self.diagnostics = diagnostics
        super.init()
    }

    func configureForLaunch(isAutomatedMode: Bool) {
        guard !didConfigure else { return }
        didConfigure = true

        guard !isAutomatedMode else {
            RuntimeLogger.log("UpdateManager disabled in automated test mode")
            updateStatus(AppStrings.updatesDisabledAutomatedMode)
            return
        }

        guard !Self.isDevelopmentBuild else {
            RuntimeLogger.log("UpdateManager disabled in development build")
            canCheckForUpdates = false
            updateStatus(AppStrings.updatesDisabledDevelopmentBuild)
            return
        }

        guard !Self.requiresSparkleInstallerLauncherService || Self.hasInstalledSparkleInstallerLauncherService else {
            RuntimeLogger.log("UpdateManager disabled because Sparkle launcher service is missing from app bundle")
            canCheckForUpdates = false
            updateStatus(AppStrings.updatesUnavailableIncompleteRuntime)
            return
        }

        RuntimeLogger.log("UpdateManager configuring updater (requiresLauncherService=\(Self.requiresSparkleInstallerLauncherService))")
        updaterController.startUpdater()
        bindUpdaterState()
        bindSettings()
        performLaunchUpdateCheckIfNeeded()
        rescheduleAutomaticChecks()
    }

    func checkForUpdates() {
        guard didConfigure else { return }
        guard updaterController.updater.canCheckForUpdates else { return }
        settings.markUpdateCheckNow()
        RuntimeLogger.log("User initiated update check (interactive mode)")
        beginManualUpdateCheck()
        updateStatus(AppStrings.updateCheckingStatusMessage)
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    private func bindUpdaterState() {
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        settings.$updateCheckFrequency
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.rescheduleAutomaticChecks()
            }
            .store(in: &cancellables)
    }

    private func performLaunchUpdateCheckIfNeeded() {
        guard settings.shouldCheckForUpdatesOnLaunch() else { return }
        performBackgroundUpdateCheck()
    }

    private func rescheduleAutomaticChecks() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil

        guard let interval = settings.updateCheckFrequency.interval else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performBackgroundUpdateCheck()
            }
        }
        timer.tolerance = min(300, interval * 0.15)
        updateCheckTimer = timer
    }

    private func performBackgroundUpdateCheck() {
        guard updaterController.updater.canCheckForUpdates else { return }
        RuntimeLogger.log("Running scheduled launch/background update check")
        settings.markUpdateCheckNow()
        updaterController.updater.checkForUpdatesInBackground()
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        let base = "https://raw.githubusercontent.com/apotenza92/macsimize/main/appcasts"
        let channel = Self.isBetaBuild ? "beta" : "stable"
        let arch = Self.architectureSuffix
        return "\(base)/\(channel)-\(arch).xml"
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        RuntimeLogger.log("Sparkle appcast loaded successfully")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        finishManualUpdateCheck()
        let version = item.displayVersionString
        RuntimeLogger.log("Sparkle found update: \(version)")
        updateStatus(AppStrings.updateAvailable(version: version))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        finishManualUpdateCheck()
        RuntimeLogger.log("Sparkle did not find an update: \(error.localizedDescription)")
        updateStatus(AppStrings.updateUpToDateStatusMessage)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        finishManualUpdateCheck()
        RuntimeLogger.log("Sparkle did not find an update")
        updateStatus(AppStrings.updateUpToDateStatusMessage)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let priorStatusMessage = updateStatusMessage
        finishManualUpdateCheck()
        RuntimeLogger.log("Sparkle aborted update cycle: \(error.localizedDescription)")
        if let message = Self.statusMessage(forSparkleError: error, currentStatusMessage: priorStatusMessage) {
            updateStatus(message)
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let priorStatusMessage = updateStatusMessage
        finishManualUpdateCheck()

        if let error {
            RuntimeLogger.log("Sparkle finished update cycle with error: \(error.localizedDescription)")
            if let message = Self.statusMessage(
                forSparkleError: error,
                currentStatusMessage: priorStatusMessage
            ) {
                updateStatus(message)
            }
        } else {
            RuntimeLogger.log("Sparkle finished update cycle (\(String(describing: updateCheck)))")
            if let message = Self.statusMessageForCompletedUpdateCycle(currentStatusMessage: priorStatusMessage) {
                updateStatus(message)
            }
        }
    }

    nonisolated private static var isBetaBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".beta") == true
    }

    nonisolated private static var architectureSuffix: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    nonisolated private static var isDevelopmentBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    nonisolated static func sparkleInstallerLauncherServicePath(bundleIdentifier: String, bundleURL: URL) -> String {
        let launcherServiceName = "\(bundleIdentifier)-spks.xpc"
        return bundleURL
            .appendingPathComponent("Contents/XPCServices/\(launcherServiceName)")
            .path
    }

    nonisolated static func hasSparkleInstallerLauncherService(
        bundleIdentifier: String,
        bundleURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let launcherPath = sparkleInstallerLauncherServicePath(
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL
        )
        return fileManager.fileExists(atPath: launcherPath)
    }

    nonisolated private static var requiresSparkleInstallerLauncherService: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SUEnableInstallerLauncherService") as? Bool) ?? true
    }

    nonisolated private static var hasInstalledSparkleInstallerLauncherService: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return false
        }

        return hasSparkleInstallerLauncherService(
            bundleIdentifier: bundleId,
            bundleURL: Bundle.main.bundleURL
        )
    }

    nonisolated static func statusMessage(forSparkleError error: Error, currentStatusMessage: String?) -> String? {
        let sparkleError = error as NSError

        if sparkleError.domain == SUSparkleErrorDomain {
            switch sparkleError.code {
            case SparkleErrorCode.noUpdate:
                return AppStrings.updateUpToDateStatusMessage
            case SparkleErrorCode.installationCanceled, SparkleErrorCode.installationAuthorizeLater:
                return nil
            default:
                break
            }
        }

        switch currentStatusMessage {
        case AppStrings.updateUpToDateStatusMessage, nil:
            return nil
        case let message? where message.hasPrefix(AppStrings.updateAvailable(version: "")):
            return nil
        default:
            return AppStrings.updateCheckFailedStatusMessage
        }
    }

    nonisolated static func statusMessageForCompletedUpdateCycle(currentStatusMessage: String?) -> String? {
        switch currentStatusMessage {
        case AppStrings.updateCheckingStatusMessage, AppStrings.updateCheckSlowStatusMessage:
            return AppStrings.updateUpToDateStatusMessage
        default:
            return nil
        }
    }

    nonisolated static func hasAvailableUpdateStatusMessage(_ message: String?) -> Bool {
        message?.hasPrefix(AppStrings.updateAvailable(version: "")) == true
    }

    private func beginManualUpdateCheck() {
        isCheckingForUpdates = true
        manualCheckStatusTimeoutTask?.cancel()
        manualCheckStatusTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Timing.manualCheckStatusTimeoutNanoseconds)
            } catch {
                return
            }

            guard let self, self.isCheckingForUpdates else { return }

            RuntimeLogger.log("Manual update check is taking longer than expected")
            self.isCheckingForUpdates = false
            if self.updateStatusMessage == AppStrings.updateCheckingStatusMessage {
                self.updateStatus(AppStrings.updateCheckSlowStatusMessage)
            }
            self.manualCheckStatusTimeoutTask = nil
        }
    }

    private func finishManualUpdateCheck() {
        isCheckingForUpdates = false
        manualCheckStatusTimeoutTask?.cancel()
        manualCheckStatusTimeoutTask = nil
    }

    private func updateStatus(_ message: String) {
        updateStatusMessage = message
        diagnostics.logMessage(message)
    }
}
