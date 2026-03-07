import Foundation

struct MaximizeResult: Equatable {
    let succeeded: Bool
    let appliedRect: CGRect?
    let restored: Bool
    let positionApplied: Bool
    let postApplyFrame: CGRect?
    let notes: [String]
}

protocol MaximizePerforming {
    func perform(on context: ClickedWindowContext) -> MaximizeResult
}

final class MaximizeStrategy: MaximizePerforming {
    private let frameStore: WindowFrameStore
    private let diagnostics: DebugDiagnostics
    private let screenProvider: () -> [ScreenDescriptor]

    init(
        frameStore: WindowFrameStore,
        diagnostics: DebugDiagnostics,
        screenProvider: @escaping () -> [ScreenDescriptor] = ScreenHelpers.currentScreens
    ) {
        self.frameStore = frameStore
        self.diagnostics = diagnostics
        self.screenProvider = screenProvider
    }

    func perform(on context: ClickedWindowContext) -> MaximizeResult {
        guard let currentFrame = context.windowFrame else {
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: false, positionApplied: false, postApplyFrame: nil, notes: ["Window frame unavailable."])
        }

        guard context.canSetSize else {
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: false, positionApplied: false, postApplyFrame: currentFrame, notes: ["Window size is not settable."])
        }

        let screens = screenProvider()
        guard let chosenScreen = ScreenHelpers.bestScreen(for: currentFrame, screens: screens) else {
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: false, positionApplied: false, postApplyFrame: currentFrame, notes: ["Unable to determine a target display."])
        }

        let targetFrame = ScreenHelpers.accessibilityRect(forVisibleFrame: chosenScreen.visibleFrame, in: screens)
        let storedState = frameStore.storedState(for: context.windowIdentifier)
        let shouldRestore = Self.shouldRestore(currentFrame: currentFrame, targetFrame: targetFrame, storedState: storedState)
        let destinationFrame = shouldRestore ? (storedState?.originalFrame ?? targetFrame) : targetFrame

        var notes: [String] = []
        diagnostics.logMessage(
            "Deterministic maximize preparing for \(context.windowIdentifier): source=\(NSStringFromRect(currentFrame)) screen=\(chosenScreen.identifier) visibleFrame=\(NSStringFromRect(targetFrame)) destination=\(NSStringFromRect(destinationFrame)) restore=\(shouldRestore)"
        )

        var positionApplied = false
        if context.canSetPosition {
            let positionError = AXHelpers.set(position: destinationFrame.origin, on: context.windowElement)
            if positionError == .success {
                positionApplied = true
            } else {
                notes.append("AXPosition set failed with \(positionError.rawValue).")
            }
        } else {
            notes.append("AXPosition is not settable for this window; resized only.")
        }

        let sizeError = AXHelpers.set(size: destinationFrame.size, on: context.windowElement)
        guard sizeError == .success else {
            notes.append("AXSize set failed with \(sizeError.rawValue).")
            diagnostics.logMessage("Deterministic maximize failed for \(context.windowIdentifier): \(notes.joined(separator: " "))")
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: shouldRestore, positionApplied: positionApplied, postApplyFrame: AXHelpers.cgRect(of: context.windowElement), notes: notes)
        }

        let postApplyFrame = AXHelpers.pollWindowFrame(of: context.windowElement)
        if let postApplyFrame, !Self.framesNearlyEqual(postApplyFrame, destinationFrame) {
            notes.append("Post-apply frame differs from the requested destination.")
        }

        if shouldRestore {
            frameStore.removeStoredFrame(for: context.windowIdentifier)
            notes.append("Restored the previously stored frame.")
        } else {
            let effectiveMaximizedFrame = postApplyFrame ?? destinationFrame
            if !Self.framesNearlyEqual(currentFrame, effectiveMaximizedFrame) {
                frameStore.storeTransition(
                    originalFrame: currentFrame,
                    maximizedFrame: effectiveMaximizedFrame,
                    for: context.windowIdentifier
                )
            }
        }

        diagnostics.logMessage(
            "Deterministic maximize applied to \(context.windowIdentifier): source=\(NSStringFromRect(currentFrame)) screen=\(chosenScreen.identifier) visibleFrame=\(NSStringFromRect(targetFrame)) destination=\(NSStringFromRect(destinationFrame)) post=\(postApplyFrame.map { NSStringFromRect($0) } ?? "-") positionApplied=\(positionApplied)"
        )
        return MaximizeResult(succeeded: true, appliedRect: destinationFrame, restored: shouldRestore, positionApplied: positionApplied, postApplyFrame: postApplyFrame, notes: notes)
    }

    static func targetRect(for windowFrame: CGRect, screens: [ScreenDescriptor]) -> CGRect? {
        ScreenHelpers.maximizeRect(for: windowFrame, screens: screens)
    }

    static func shouldRestore(currentFrame: CGRect, targetFrame: CGRect, storedState: StoredWindowFrameState?) -> Bool {
        guard let storedState else {
            return false
        }

        if let lastAppliedMaximizeFrame = storedState.lastAppliedMaximizeFrame {
            let nearMaximizedState = framesNearlyEqual(currentFrame, lastAppliedMaximizeFrame) ||
                framesNearlyEqual(currentFrame, targetFrame)
            return nearMaximizedState && !framesNearlyEqual(storedState.originalFrame, currentFrame)
        }

        return framesNearlyEqual(currentFrame, targetFrame) && !framesNearlyEqual(storedState.originalFrame, targetFrame)
    }

    static func framesNearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
