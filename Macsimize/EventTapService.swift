import AppKit
import ApplicationServices
import Foundation

final class EventTapService: ObservableObject, @unchecked Sendable {
    @Published private(set) var isRunning = false
    @Published private(set) var lastFailureReason: String?

    private let settings: SettingsStore
    private let permissions: PermissionsCoordinator
    private let diagnostics: DebugDiagnostics
    private let controller: GreenButtonInterceptionController
    private let titleBarController: TitleBarInterceptionController
    private let actionPerformer: WindowActionPerforming
    private let dragRestorePerformer: DragRestorePerforming

    private let callbackQueue = DispatchQueue(label: "Macsimize.EventTap.Callback")
    private let actionQueue = DispatchQueue(label: "Macsimize.EventTap.Action")
    private let stateQueue = DispatchQueue(label: "Macsimize.EventTap.State")

    private var configuration: InterceptionConfiguration
    private var bufferedEvents: [CGEvent] = []
    private var holdTimer: DispatchSourceTimer?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var postActionSuppressionUntilByPID: [pid_t: TimeInterval] = [:]
    private let deferredReplayStore = DeferredReplayStore()
    private let postActionSuppressionDuration: TimeInterval = 0.6

    init(
        settings: SettingsStore,
        permissions: PermissionsCoordinator,
        accessibilityService: AccessibilityService,
        actionEngine: WindowActionEngine,
        maximizeStrategy: MaximizeStrategy,
        diagnostics: DebugDiagnostics
    ) {
        self.settings = settings
        self.permissions = permissions
        self.diagnostics = diagnostics
        self.controller = GreenButtonInterceptionController(
            contextResolver: accessibilityService,
            diagnostics: diagnostics
        )
        self.titleBarController = TitleBarInterceptionController(
            contextResolver: accessibilityService,
            diagnostics: diagnostics
        )
        self.actionPerformer = actionEngine
        self.dragRestorePerformer = maximizeStrategy
        self.configuration = InterceptionConfiguration(
            selectedAction: settings.selectedAction,
            diagnosticsEnabled: settings.diagnosticsEnabled
        )
    }

    func refreshConfiguration(
        selectedAction: WindowActionMode? = nil,
        diagnosticsEnabled: Bool? = nil
    ) {
        stateQueue.sync {
            configuration = InterceptionConfiguration(
                selectedAction: selectedAction ?? settings.selectedAction,
                diagnosticsEnabled: diagnosticsEnabled ?? settings.diagnosticsEnabled
            )
        }
    }

    func startIfPossible(
        selectedAction: WindowActionMode? = nil,
        diagnosticsEnabled: Bool? = nil
    ) {
        refreshConfiguration(
            selectedAction: selectedAction,
            diagnosticsEnabled: diagnosticsEnabled
        )
        let hadActiveTap = eventTap != nil || isRunning

        guard permissions.state.accessibilityTrusted else {
            if hadActiveTap {
                RuntimeLogger.log("startIfPossible: denied (no accessibility).")
            }
            stop(reason: "Accessibility permission has not been granted yet.")
            return
        }

        guard permissions.state.inputMonitoringGranted else {
            if hadActiveTap {
                RuntimeLogger.log("startIfPossible: denied (no input monitoring).")
            }
            stop(reason: "Input Monitoring has not been granted yet.")
            return
        }

        if permissions.state.secureEventInputEnabled {
            RuntimeLogger.log("startIfPossible: Secure Event Input is enabled; event interception may be limited.")
        }

        guard eventTap == nil else {
            updateRunningState(true, failure: nil)
            return
        }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let service = Unmanaged<EventTapService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            RuntimeLogger.log("Failed to start event tap.")
            updateRunningState(false, failure: AppStrings.eventTapUnavailableFailureReason)
            diagnostics.logMessage(AppStrings.eventTapCreationFailed, forceVisible: true)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        RuntimeLogger.log("Event tap started.")
        updateRunningState(true, failure: nil)
    }

    func restart() {
        stop(reason: nil)
        startIfPossible()
    }

    func stop(reason: String?) {
        let hadActiveTap = eventTap != nil || isRunning
        if let reason, hadActiveTap {
            RuntimeLogger.log("Stopping event tap: \(reason)")
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil

        callbackQueue.sync {
            cancelHoldTimer()
            bufferedEvents.removeAll()
            controller.reset()
            titleBarController.reset()
            postActionSuppressionUntilByPID.removeAll()
            deferredReplayStore.removeAll()
        }

        updateRunningState(false, failure: reason)
    }

    private func updateRunningState(_ running: Bool, failure: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard self.isRunning != running || self.lastFailureReason != failure else {
                return
            }
            self.isRunning = running
            self.lastFailureReason = failure
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == WindowActionEngine.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            callbackQueue.sync {
                cancelHoldTimer()
                bufferedEvents.removeAll()
                controller.reset()
                titleBarController.reset()
                deferredReplayStore.removeAll()
            }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            diagnostics.logMessage(AppStrings.eventTapReenabledMessage)
            return Unmanaged.passUnretained(event)
        }

        guard type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp else {
            return Unmanaged.passUnretained(event)
        }

        return callbackQueue.sync {
            let config = stateQueue.sync { configuration }
            switch type {
            case .leftMouseDown:
                return processMouseDown(event, configuration: config)
            case .leftMouseDragged:
                return processMouseDragged(event)
            case .leftMouseUp:
                return processMouseUp(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }
    }

    private func processMouseDown(_ event: CGEvent, configuration: InterceptionConfiguration) -> Unmanaged<CGEvent>? {
        if shouldBypassInterception(for: event.location) {
            return Unmanaged.passUnretained(event)
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        if shouldSuppressInterception(now: timestamp) {
            return Unmanaged.passUnretained(event)
        }

        let greenButtonDecision = controller.handleMouseDown(
            location: event.location,
            timestamp: timestamp,
            optionPressed: event.flags.contains(.maskAlternate),
            configuration: configuration
        )

        switch greenButtonDecision {
        case .passThrough:
            break
        case .consume:
            guard let copiedEvent = event.copy() else {
                return Unmanaged.passUnretained(event)
            }
            bufferedEvents = [copiedEvent]
            scheduleHoldTimer()
            return nil
        case .flushBufferedEvents:
            return Unmanaged.passUnretained(event)
        case .performAction:
            return Unmanaged.passUnretained(event)
        }

        let titleBarDecision = titleBarController.handleMouseDown(
            location: event.location,
            clickCount: event.getIntegerValueField(.mouseEventClickState),
            configuration: configuration
        )

        switch titleBarDecision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .consume:
            return nil
        case .performAction(let context):
            performTitleBarWindowActionAsync(context)
            return nil
        case .dragRestore:
            return Unmanaged.passUnretained(event)
        }
    }

    private func processMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !bufferedEvents.isEmpty else {
            switch titleBarController.handleMouseDragged(location: event.location) {
            case .dragRestore(let context, let cursorLocation):
                let result = dragRestorePerformer.performDragRestore(on: context, cursorLocation: cursorLocation)
                if !result.restored {
                    diagnostics.logMessage(result.notes.first ?? AppStrings.titleBarDragRestoreSkipped)
                }
                return Unmanaged.passUnretained(event)
            case .passThrough, .consume, .performAction:
                return Unmanaged.passUnretained(event)
            }
        }

        if let copiedEvent = event.copy() {
            bufferedEvents.append(copiedEvent)
        }

        switch controller.handleMouseDragged(location: event.location) {
        case .consume:
            return nil
        case .flushBufferedEvents:
            flushBufferedEvents()
            return nil
        case .passThrough:
            cancelHoldTimer()
            bufferedEvents.removeAll()
            return Unmanaged.passUnretained(event)
        case .performAction:
            return nil
        }
    }

    private func processMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !bufferedEvents.isEmpty else {
            switch titleBarController.handleMouseUp() {
            case .consume:
                return nil
            case .passThrough, .dragRestore, .performAction:
                return Unmanaged.passUnretained(event)
            }
        }

        let decision = controller.handleMouseUp(
            location: event.location,
            timestamp: ProcessInfo.processInfo.systemUptime
        )

        switch decision {
        case .passThrough:
            cancelHoldTimer()
            bufferedEvents.removeAll()
            return Unmanaged.passUnretained(event)
        case .consume:
            return nil
        case .flushBufferedEvents:
            if let copiedEvent = event.copy() {
                bufferedEvents.append(copiedEvent)
            }
            flushBufferedEvents()
            return nil
        case .performAction(let pendingAction):
            cancelHoldTimer()
            var originalSequence = bufferedEvents
            if let copiedEvent = event.copy() {
                originalSequence.append(copiedEvent)
            }
            bufferedEvents.removeAll()
            let replaySequence = Self.replaySequence(for: pendingAction.mode, originalEvents: originalSequence)
            let replayToken = storeDeferredReplaySequence(replaySequence)
            performWindowActionAsync(pendingAction, replayToken: replayToken)
            return nil
        }
    }

    private func scheduleHoldTimer() {
        cancelHoldTimer()
        let timer = DispatchSource.makeTimerSource(queue: callbackQueue)
        timer.schedule(deadline: .now() + 0.35)
        timer.setEventHandler { [weak self] in
            self?.processHoldTimeout()
        }
        holdTimer = timer
        timer.resume()
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func processHoldTimeout() {
        guard !bufferedEvents.isEmpty else {
            cancelHoldTimer()
            return
        }

        switch controller.handleHoldTimeout(timestamp: ProcessInfo.processInfo.systemUptime) {
        case .flushBufferedEvents:
            flushBufferedEvents()
        case .consume:
            break
        case .passThrough:
            cancelHoldTimer()
            bufferedEvents.removeAll()
        case .performAction:
            break
        }
    }

    private func flushBufferedEvents() {
        cancelHoldTimer()
        let eventsToReplay = bufferedEvents
        bufferedEvents.removeAll()
        replayOriginalMouseSequence(eventsToReplay)
    }

    private func performWindowActionAsync(_ pendingAction: PendingWindowAction, replayToken: UUID) {
        let mode = pendingAction.mode
        let context = pendingAction.context
        let windowPID = pendingAction.context.pid
        actionQueue.async { [weak self] in
            guard let self else {
                return
            }

            let outcome = self.actionPerformer.perform(mode: mode, context: context)
            if outcome.handled {
                self.callbackQueue.async { [weak self] in
                    self?.clearDeferredReplaySequence(for: replayToken)
                    self?.recordPostActionSuppression(for: windowPID, now: ProcessInfo.processInfo.systemUptime)
                }
                return
            }

            switch outcome.failureDisposition {
            case .replayOriginalClick:
                self.callbackQueue.async { [weak self] in
                    self?.diagnostics.logMessage(AppStrings.eventTapReplayOriginalSequence)
                    self?.replayDeferredReplaySequence(for: replayToken)
                }
            case .dropInterceptedClick:
                self.callbackQueue.async { [weak self] in
                    self?.clearDeferredReplaySequence(for: replayToken)
                    self?.diagnostics.logMessage(AppStrings.eventTapSwallowNativeSequence)
                }
            }
        }
    }

    private func performTitleBarWindowActionAsync(_ context: ClickedWindowContext) {
        actionQueue.async { [weak self] in
            guard let self else {
                return
            }

            let outcome = self.actionPerformer.perform(mode: .maximize, context: context)
            if outcome.handled {
                self.callbackQueue.async { [weak self] in
                    self?.recordPostActionSuppression(for: context.pid, now: ProcessInfo.processInfo.systemUptime)
                }
            }
        }
    }

    private func replayOriginalMouseSequence(_ events: [CGEvent]) {
        for event in events {
            guard let copiedEvent = event.copy() else {
                continue
            }
            copiedEvent.setIntegerValueField(.eventSourceUserData, value: WindowActionEngine.syntheticEventMarker)
            copiedEvent.post(tap: .cghidEventTap)
        }
    }

    private func storeDeferredReplaySequence(_ events: [CGEvent]) -> UUID {
        deferredReplayStore.store(events)
    }

    private func replayDeferredReplaySequence(for token: UUID) {
        let events = deferredReplayStore.take(token) ?? []
        replayOriginalMouseSequence(events)
    }

    private func clearDeferredReplaySequence(for token: UUID) {
        deferredReplayStore.remove(token)
    }

    private func shouldBypassInterception(for location: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return false
        }
        return location.y > screen.visibleFrame.maxY
    }

    private func shouldSuppressInterception(now: TimeInterval) -> Bool {
        pruneExpiredSuppressions(now: now)
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        guard let suppressedUntil = postActionSuppressionUntilByPID[frontmostPID] else {
            return false
        }
        if now < suppressedUntil {
            return true
        }
        postActionSuppressionUntilByPID.removeValue(forKey: frontmostPID)
        return false
    }

    private func recordPostActionSuppression(for pid: pid_t, now: TimeInterval) {
        postActionSuppressionUntilByPID[pid] = now + postActionSuppressionDuration
    }

    private func pruneExpiredSuppressions(now: TimeInterval) {
        for (pid, deadline) in Array(postActionSuppressionUntilByPID) where deadline <= now {
            postActionSuppressionUntilByPID.removeValue(forKey: pid)
        }
    }

    static func replaySequence(for mode: WindowActionMode, originalEvents: [CGEvent]) -> [CGEvent] {
        guard mode == .fullScreen else {
            return originalEvents
        }

        return originalEvents.compactMap { event in
            guard let copiedEvent = event.copy() else {
                return nil
            }
            copiedEvent.flags.remove(.maskAlternate)
            return copiedEvent
        }
    }

    deinit {
        stop(reason: nil)
    }
}

extension WindowActionEngine: WindowActionPerforming {}
extension MaximizeStrategy: DragRestorePerforming {}

protocol WindowActionPerforming {
    func perform(mode: WindowActionMode, context: ClickedWindowContext) -> WindowActionOutcome
}

protocol DragRestorePerforming {
    func performDragRestore(on context: ClickedWindowContext, cursorLocation: CGPoint) -> DragRestoreResult
}

final class DeferredReplayStore {
    private var eventsByToken: [UUID: [CGEvent]] = [:]

    func store(_ events: [CGEvent]) -> UUID {
        let token = UUID()
        eventsByToken[token] = events
        return token
    }

    func take(_ token: UUID) -> [CGEvent]? {
        eventsByToken.removeValue(forKey: token)
    }

    func remove(_ token: UUID) {
        eventsByToken.removeValue(forKey: token)
    }

    func removeAll() {
        eventsByToken.removeAll()
    }

    var isEmpty: Bool {
        eventsByToken.isEmpty
    }
}
