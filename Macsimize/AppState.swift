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
        updateManager = UpdateManager(settings: settings, diagnostics: diagnostics)
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
            maximizeStrategy: maximizeStrategy,
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

    func setSelectedAction(_ selectedAction: WindowActionMode) {
        guard settings.selectedAction != selectedAction else {
            return
        }
        settings.selectedAction = selectedAction
        refreshLiveInterceptionConfiguration(selectedAction: selectedAction)
    }

    func captureDiagnosticsSnapshot() {
        accessibilityService.captureFrontmostWindowSnapshot()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        permissions.startMonitoringForChanges()
        refreshPermissions(promptIfNeeded: false)
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        permissions.startMonitoringForChanges()
        refreshPermissions(promptIfNeeded: false)
    }

    func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = RelaunchSupport.launchArguments(
            from: ProcessInfo.processInfo.arguments,
            openSettingsArguments: ["--settings", "-settings", "--open-settings"],
            nextAutomaticRelaunchAttempt: nil
        )

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [diagnostics] _, error in
            if let error {
                diagnostics.logMessage(AppStrings.relaunchFailed(errorDescription: error.localizedDescription), forceVisible: true)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        }
    }

    func maximizeAllCurrentSpaceWindows() {
        let diagnosticsEnabled = settings.diagnosticsEnabled
        DispatchQueue.global(qos: .userInitiated).async { [accessibilityService, maximizeStrategy, diagnostics] in
            let batchStart = CFAbsoluteTimeGetCurrent()
            let actionQueue = DispatchQueue(label: "Macsimize.BatchMaximize.Action")
            let actionGroup = DispatchGroup()
            let metrics = BatchExecutionMetrics()

            let scan = accessibilityService.enumerateCurrentSpaceWindowsForMaximize { context in
                actionGroup.enter()
                actionQueue.async {
                    metrics.recordActionQueued(batchStart: batchStart)

                    let actionStart = CFAbsoluteTimeGetCurrent()
                    let result = maximizeStrategy.perform(on: context)
                    let actionDuration = Self.millisecondsSince(actionStart)

                    if result.succeeded {
                        metrics.recordSuccess(durationMs: actionDuration)
                    } else {
                        metrics.recordSkip(reason: result.notes.joined(separator: "; "), durationMs: actionDuration)
                        diagnostics.logMessage(
                            AppStrings.maximizeAllWindowSkipped(
                                reason: result.notes.joined(separator: "; "),
                                identifier: context.windowIdentifier
                            )
                        )
                    }

                    actionGroup.leave()
                }
            }
            let enumerationMs = Self.millisecondsSince(batchStart)
            actionGroup.wait()
            let snapshot = metrics.snapshot

            guard snapshot.attemptedCount > 0 else {
                diagnostics.logMessage(
                    AppStrings.maximizeAllTimingSummary(
                        appCount: scan.enumeratedAppCount,
                        candidateCount: scan.candidateCount,
                        eligibleCount: 0,
                        cgEntryCount: scan.cgEntryCount,
                        activeSpaceCount: scan.activeSpaceCount,
                        resolvedWindowIDCount: scan.resolvedWindowIDCount,
                        spaceResolvedCandidateCount: scan.spaceResolvedCandidateCount,
                        enumerationMs: enumerationMs,
                        firstActionMs: snapshot.firstActionMs,
                        actionMs: 0,
                        averageWindowMs: 0,
                        slowestWindowMs: 0,
                        totalMs: Self.millisecondsSince(batchStart)
                    )
                )
                diagnostics.logMessage(AppStrings.maximizeAllNoEligibleWindows, forceVisible: true)
                return
            }

            let actionTiming = Self.actionTimingSummary(for: snapshot.actionDurations)
            diagnostics.logMessage(
                AppStrings.maximizeAllTimingSummary(
                    appCount: scan.enumeratedAppCount,
                    candidateCount: scan.candidateCount,
                    eligibleCount: snapshot.attemptedCount,
                    cgEntryCount: scan.cgEntryCount,
                    activeSpaceCount: scan.activeSpaceCount,
                    resolvedWindowIDCount: scan.resolvedWindowIDCount,
                    spaceResolvedCandidateCount: scan.spaceResolvedCandidateCount,
                    enumerationMs: enumerationMs,
                    firstActionMs: snapshot.firstActionMs,
                    actionMs: actionTiming.total,
                    averageWindowMs: actionTiming.average,
                    slowestWindowMs: actionTiming.slowest,
                    totalMs: Self.millisecondsSince(batchStart)
                ),
                forceVisible: true
            )
            if let skipSummary = Self.skipSummaryString(snapshot.skipCounts) {
                diagnostics.logMessage(
                    AppStrings.maximizeAllSkipSummary(skipSummary),
                    forceVisible: diagnosticsEnabled || snapshot.skippedCount > 0
                )
            }
            diagnostics.logMessage(
                AppStrings.maximizeAllFinished(processedCount: snapshot.processedCount, skippedCount: snapshot.skippedCount),
                forceVisible: true
            )
        }
    }

    func restoreAllCurrentSpaceWindows() {
        let diagnosticsEnabled = settings.diagnosticsEnabled
        DispatchQueue.global(qos: .userInitiated).async { [accessibilityService, maximizeStrategy, diagnostics, frameStore] in
            let batchStart = CFAbsoluteTimeGetCurrent()
            let managedIdentifiers = frameStore.managedWindowIdentifiers()

            guard !managedIdentifiers.isEmpty else {
                diagnostics.logMessage(
                    AppStrings.restoreAllTimingSummary(
                        appCount: 0,
                        candidateCount: 0,
                        eligibleCount: 0,
                        cgEntryCount: 0,
                        activeSpaceCount: 0,
                        resolvedWindowIDCount: 0,
                        spaceResolvedCandidateCount: 0,
                        enumerationMs: 0,
                        firstActionMs: nil,
                        actionMs: 0,
                        averageWindowMs: 0,
                        slowestWindowMs: 0,
                        totalMs: Self.millisecondsSince(batchStart)
                    )
                )
                diagnostics.logMessage(AppStrings.restoreAllNoEligibleWindows, forceVisible: true)
                return
            }

            let actionQueue = DispatchQueue(label: "Macsimize.BatchRestore.Action")
            let actionGroup = DispatchGroup()
            let metrics = BatchExecutionMetrics()

            let scan = accessibilityService.enumerateCurrentSpaceWindowsForMaximize(
                matchingIdentifiers: managedIdentifiers
            ) { context in
                actionGroup.enter()
                actionQueue.async {
                    guard maximizeStrategy.isCurrentlyManagedMaximized(context) else {
                        metrics.recordSkip(reason: AppStrings.restoreAllSkipReasonNotManagedMaximized)
                        if diagnosticsEnabled {
                            diagnostics.logMessage(
                                AppStrings.restoreAllWindowSkipped(
                                    reason: AppStrings.restoreAllSkipReasonNotManagedMaximized,
                                    identifier: context.windowIdentifier
                                )
                            )
                        }
                        actionGroup.leave()
                        return
                    }

                    metrics.recordActionQueued(batchStart: batchStart)

                    let actionStart = CFAbsoluteTimeGetCurrent()
                    let result = maximizeStrategy.perform(on: context)
                    let actionDuration = Self.millisecondsSince(actionStart)

                    if result.succeeded, result.restored {
                        metrics.recordSuccess(durationMs: actionDuration)
                    } else {
                        let notes = result.notes.isEmpty
                            ? [AppStrings.restoreAllSkipReasonNotManagedMaximized]
                            : result.notes
                        metrics.recordSkip(reason: notes.joined(separator: "; "), durationMs: actionDuration)
                        if !result.succeeded {
                            diagnostics.logMessage(
                                AppStrings.restoreAllWindowSkipped(
                                    reason: notes.joined(separator: "; "),
                                    identifier: context.windowIdentifier
                                )
                            )
                        }
                    }

                    actionGroup.leave()
                }
            }
            let enumerationMs = Self.millisecondsSince(batchStart)
            actionGroup.wait()
            let snapshot = metrics.snapshot

            guard snapshot.attemptedCount > 0 else {
                diagnostics.logMessage(
                    AppStrings.restoreAllTimingSummary(
                        appCount: scan.enumeratedAppCount,
                        candidateCount: scan.candidateCount,
                        eligibleCount: 0,
                        cgEntryCount: scan.cgEntryCount,
                        activeSpaceCount: scan.activeSpaceCount,
                        resolvedWindowIDCount: scan.resolvedWindowIDCount,
                        spaceResolvedCandidateCount: scan.spaceResolvedCandidateCount,
                        enumerationMs: enumerationMs,
                        firstActionMs: snapshot.firstActionMs,
                        actionMs: 0,
                        averageWindowMs: 0,
                        slowestWindowMs: 0,
                        totalMs: Self.millisecondsSince(batchStart)
                    )
                )
                if let skipSummary = Self.skipSummaryString(snapshot.skipCounts) {
                    diagnostics.logMessage(
                        AppStrings.restoreAllSkipSummary(skipSummary),
                        forceVisible: diagnosticsEnabled || snapshot.skippedCount > 0
                    )
                }
                diagnostics.logMessage(AppStrings.restoreAllNoEligibleWindows, forceVisible: true)
                return
            }

            let actionTiming = Self.actionTimingSummary(for: snapshot.actionDurations)
            diagnostics.logMessage(
                AppStrings.restoreAllTimingSummary(
                    appCount: scan.enumeratedAppCount,
                    candidateCount: scan.candidateCount,
                    eligibleCount: snapshot.attemptedCount,
                    cgEntryCount: scan.cgEntryCount,
                    activeSpaceCount: scan.activeSpaceCount,
                    resolvedWindowIDCount: scan.resolvedWindowIDCount,
                    spaceResolvedCandidateCount: scan.spaceResolvedCandidateCount,
                    enumerationMs: enumerationMs,
                    firstActionMs: snapshot.firstActionMs,
                    actionMs: actionTiming.total,
                    averageWindowMs: actionTiming.average,
                    slowestWindowMs: actionTiming.slowest,
                    totalMs: Self.millisecondsSince(batchStart)
                ),
                forceVisible: true
            )
            if let skipSummary = Self.skipSummaryString(snapshot.skipCounts) {
                diagnostics.logMessage(
                    AppStrings.restoreAllSkipSummary(skipSummary),
                    forceVisible: diagnosticsEnabled || snapshot.skippedCount > 0
                )
            }
            diagnostics.logMessage(
                AppStrings.restoreAllFinished(processedCount: snapshot.processedCount, skippedCount: snapshot.skippedCount),
                forceVisible: true
            )
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
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
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

    nonisolated private static func millisecondsSince(_ start: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }

    nonisolated private static func actionTimingSummary(for durations: [Double]) -> (total: Double, average: Double, slowest: Double) {
        let total = durations.reduce(0, +)
        let average = durations.isEmpty ? 0 : (total / Double(durations.count))
        let slowest = durations.max() ?? 0
        return (total, average, slowest)
    }

    nonisolated private static func skipSummaryString(_ skipCounts: [String: Int]) -> String? {
        guard !skipCounts.isEmpty else {
            return nil
        }
        return skipCounts.keys.sorted().map { key in
            "\(key)=\(skipCounts[key] ?? 0)"
        }.joined(separator: " | ")
    }
}

private struct BatchExecutionSnapshot {
    let processedCount: Int
    let skippedCount: Int
    let attemptedCount: Int
    let firstActionMs: Double?
    let actionDurations: [Double]
    let skipCounts: [String: Int]
}

private final class BatchExecutionMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var processedCount = 0
    private var skippedCount = 0
    private var attemptedCount = 0
    private var firstActionMs: Double?
    private var actionDurations: [Double] = []
    private var skipCounts: [String: Int] = [:]

    func recordActionQueued(batchStart: CFAbsoluteTime) {
        lock.lock()
        defer { lock.unlock() }
        attemptedCount += 1
        if firstActionMs == nil {
            firstActionMs = (CFAbsoluteTimeGetCurrent() - batchStart) * 1_000
        }
    }

    func recordSuccess(durationMs: Double) {
        lock.lock()
        defer { lock.unlock() }
        processedCount += 1
        actionDurations.append(durationMs)
    }

    func recordSkip(reason: String, durationMs: Double? = nil) {
        lock.lock()
        defer { lock.unlock() }
        skippedCount += 1
        if let durationMs {
            actionDurations.append(durationMs)
        }
        let normalizedReason = reason.isEmpty ? AppStrings.unknownLabel : reason
        skipCounts[normalizedReason, default: 0] += 1
    }

    var snapshot: BatchExecutionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return BatchExecutionSnapshot(
            processedCount: processedCount,
            skippedCount: skippedCount,
            attemptedCount: attemptedCount,
            firstActionMs: firstActionMs,
            actionDurations: actionDurations,
            skipCounts: skipCounts
        )
    }
}

enum AppIdentity {
    enum RunningIdentity: Equatable {
        case stable
        case beta
        case development
        case unknown
    }

    static let stableBundleIdentifier = "pzc.Macsimize"
    static let betaBundleIdentifier = "pzc.Macsimize.beta"
    static let developmentBundleIdentifier = "pzc.Macsimize.dev"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    static var runningIdentity: RunningIdentity {
        runningIdentity(bundleIdentifier: bundleIdentifier)
    }

    static func runningIdentity(bundleIdentifier: String?) -> RunningIdentity {
        switch bundleIdentifier ?? "" {
        case stableBundleIdentifier:
            return .stable
        case betaBundleIdentifier:
            return .beta
        case developmentBundleIdentifier:
            return .development
        default:
            return .unknown
        }
    }

    static var supportsUpdates: Bool {
        supportsUpdates(bundleIdentifier: bundleIdentifier)
    }

    static func supportsUpdates(bundleIdentifier: String?) -> Bool {
        switch runningIdentity(bundleIdentifier: bundleIdentifier) {
        case .stable, .beta:
            return true
        case .development, .unknown:
            return false
        }
    }

    static var supportsLoginItem: Bool {
        supportsLoginItem(bundleIdentifier: bundleIdentifier)
    }

    static func supportsLoginItem(bundleIdentifier: String?) -> Bool {
        switch runningIdentity(bundleIdentifier: bundleIdentifier) {
        case .stable, .beta:
            return true
        case .development, .unknown:
            return false
        }
    }

    static var updateChannelName: String? {
        updateChannelName(bundleIdentifier: bundleIdentifier)
    }

    static func updateChannelName(bundleIdentifier: String?) -> String? {
        switch runningIdentity(bundleIdentifier: bundleIdentifier) {
        case .stable:
            return "stable"
        case .beta:
            return "beta"
        case .development, .unknown:
            return nil
        }
    }

    static var displayName: String {
        displayName(bundle: .main)
    }

    static var settingsWindowTitle: String {
        AppStrings.settingsWindowTitle(appName: displayName)
    }

    static func displayName(bundle: Bundle) -> String {
        displayName(
            bundleDisplayName: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundleName: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            bundleURL: bundle.bundleURL,
            executableName: bundle.executableURL?.deletingPathExtension().lastPathComponent
        )
    }

    static func displayName(
        bundleDisplayName: String?,
        bundleName: String?,
        bundleURL: URL?,
        executableName: String?
    ) -> String {
        for candidate in [bundleDisplayName, bundleName, bundleURL?.deletingPathExtension().lastPathComponent, executableName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return "Macsimize"
    }
}
