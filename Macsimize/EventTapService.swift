import ApplicationServices
import Foundation

final class EventTapService: ObservableObject, @unchecked Sendable {
    @Published private(set) var isRunning = false
    @Published private(set) var lastFailureReason: String?

    private let settings: SettingsStore
    private let permissions: PermissionsCoordinator
    private let diagnostics: DebugDiagnostics
    private let controller: GreenButtonInterceptionController
    private let actionPerformer: WindowActionPerforming

    private let callbackQueue = DispatchQueue(label: "Macsimize.EventTap.Callback")
    private let actionQueue = DispatchQueue(label: "Macsimize.EventTap.Action")
    private let stateQueue = DispatchQueue(label: "Macsimize.EventTap.State")

    private var configuration: InterceptionConfiguration
    private var bufferedEvents: [CGEvent] = []
    private var holdTimer: DispatchSourceTimer?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        settings: SettingsStore,
        permissions: PermissionsCoordinator,
        accessibilityService: AccessibilityService,
        actionEngine: WindowActionEngine,
        diagnostics: DebugDiagnostics
    ) {
        self.settings = settings
        self.permissions = permissions
        self.diagnostics = diagnostics
        self.controller = GreenButtonInterceptionController(
            contextResolver: accessibilityService,
            diagnostics: diagnostics
        )
        self.actionPerformer = actionEngine
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
            updateRunningState(false, failure: "Unable to create the event tap. Input Monitoring may also be required when interception is enabled.")
            diagnostics.logMessage("Failed to create the event tap.", forceVisible: true)
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
            }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            diagnostics.logMessage("Event tap was temporarily disabled and then re-enabled.")
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
        let decision = controller.handleMouseDown(
            location: event.location,
            timestamp: ProcessInfo.processInfo.systemUptime,
            configuration: configuration
        )

        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
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
    }

    private func processMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !bufferedEvents.isEmpty else {
            return Unmanaged.passUnretained(event)
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
            return Unmanaged.passUnretained(event)
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
            performWindowActionAsync(pendingAction, fallbackEvents: originalSequence)
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

    private func performWindowActionAsync(_ pendingAction: PendingWindowAction, fallbackEvents: [CGEvent]) {
        actionQueue.async { [weak self] in
            guard let self else {
                return
            }

            let outcome = self.actionPerformer.perform(mode: pendingAction.mode, context: pendingAction.context)
            guard !outcome.handled else {
                return
            }

            self.diagnostics.logMessage("Window action failed after intercept; replaying the original mouse sequence.")
            self.replayOriginalMouseSequence(fallbackEvents)
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

    deinit {
        stop(reason: nil)
    }
}

extension WindowActionEngine: WindowActionPerforming {}

protocol WindowActionPerforming {
    func perform(mode: WindowActionMode, context: ClickedWindowContext) -> WindowActionOutcome
}
