import CoreGraphics
import Foundation

protocol GreenButtonContextResolving {
    func resolveGreenButtonClick(at location: CGPoint) -> ClickedWindowContext?
}

struct InterceptionConfiguration: Equatable {
    var selectedAction: WindowActionMode
    var diagnosticsEnabled: Bool
}

struct PendingWindowAction {
    let context: ClickedWindowContext
    let mode: WindowActionMode
}

enum MouseInterceptionDecision {
    case passThrough
    case consume
    case flushBufferedEvents
    case performAction(PendingWindowAction)
}

final class GreenButtonInterceptionController {
    private struct PendingIntercept {
        let context: ClickedWindowContext
        let mode: WindowActionMode
        let location: CGPoint
        let timestamp: TimeInterval
    }

    private let contextResolver: GreenButtonContextResolving
    private let diagnostics: DebugDiagnostics
    private let maxClickDuration: TimeInterval
    private let maxMovement: CGFloat

    private var pendingIntercept: PendingIntercept?

    init(
        contextResolver: GreenButtonContextResolving,
        diagnostics: DebugDiagnostics,
        maxClickDuration: TimeInterval = 0.35,
        maxMovement: CGFloat = 4
    ) {
        self.contextResolver = contextResolver
        self.diagnostics = diagnostics
        self.maxClickDuration = maxClickDuration
        self.maxMovement = maxMovement
    }

    func reset() {
        pendingIntercept = nil
    }

    func handleMouseDown(
        location: CGPoint,
        timestamp: TimeInterval,
        configuration: InterceptionConfiguration
    ) -> MouseInterceptionDecision {
        guard configuration.selectedAction == .maximize else {
            return .passThrough
        }

        guard let context = contextResolver.resolveGreenButtonClick(at: location) else {
            return .passThrough
        }

        pendingIntercept = PendingIntercept(
            context: context,
            mode: configuration.selectedAction,
            location: location,
            timestamp: timestamp
        )

        if configuration.diagnosticsEnabled {
            diagnostics.logClickContext(context, chosenPath: "captured-down")
        }

        return .consume
    }

    func handleMouseDragged(location: CGPoint) -> MouseInterceptionDecision {
        guard let pendingIntercept else {
            return .passThrough
        }

        let movedDistance = hypot(location.x - pendingIntercept.location.x, location.y - pendingIntercept.location.y)
        guard movedDistance > maxMovement else {
            return .consume
        }

        self.pendingIntercept = nil
        diagnostics.logMessage("Intercepted green-button press became a drag; flushing buffered native events.")
        return .flushBufferedEvents
    }

    func handleHoldTimeout(timestamp: TimeInterval) -> MouseInterceptionDecision {
        guard let pendingIntercept else {
            return .passThrough
        }

        guard timestamp - pendingIntercept.timestamp > maxClickDuration else {
            return .consume
        }

        self.pendingIntercept = nil
        diagnostics.logMessage("Intercepted green-button press became a hold; flushing buffered native events.")
        return .flushBufferedEvents
    }

    func handleMouseUp(location: CGPoint, timestamp: TimeInterval) -> MouseInterceptionDecision {
        guard let pending = pendingIntercept else {
            return .passThrough
        }
        pendingIntercept = nil

        let duration = timestamp - pending.timestamp
        let movedDistance = hypot(location.x - pending.location.x, location.y - pending.location.y)
        if duration > maxClickDuration || movedDistance > maxMovement {
            diagnostics.logMessage("Intercepted green-button press exceeded clean-click thresholds; flushing buffered native events.")
            return .flushBufferedEvents
        }

        return .performAction(PendingWindowAction(context: pending.context, mode: pending.mode))
    }
}

extension AccessibilityService: GreenButtonContextResolving {}
