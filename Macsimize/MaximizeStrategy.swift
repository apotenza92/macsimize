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

struct DragRestoreResult: Equatable {
    let restored: Bool
    let appliedRect: CGRect?
    let notes: [String]
}

struct RestoreFrameResolution: Equatable {
    let frame: CGRect
    let wasClamped: Bool
}

final class MaximizeStrategy: MaximizePerforming, @unchecked Sendable {
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
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: false, positionApplied: false, postApplyFrame: nil, notes: [AppStrings.maximizeWindowFrameUnavailable])
        }

        guard context.canSetSize else {
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: false, positionApplied: false, postApplyFrame: currentFrame, notes: [AppStrings.maximizeWindowSizeNotSettable])
        }

        let screens = screenProvider()
        guard let chosenScreen = ScreenHelpers.bestScreen(for: currentFrame, screens: screens) else {
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: false, positionApplied: false, postApplyFrame: currentFrame, notes: [AppStrings.maximizeTargetDisplayUnavailable])
        }

        let targetFrame = ScreenHelpers.accessibilityRect(forVisibleFrame: chosenScreen.visibleFrame, in: screens)
        let storedState = frameStore.storedState(for: context.windowIdentifier)
        let shouldRestore = Self.shouldRestore(currentFrame: currentFrame, targetFrame: targetFrame, storedState: storedState)
        let restoreResolution = shouldRestore
            ? storedState.flatMap { Self.resolvedRestoreFrame(currentFrame: currentFrame, storedState: $0, screens: screens) }
            : nil
        let destinationFrame = restoreResolution?.frame ?? targetFrame

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
                notes.append(AppStrings.maximizePositionSetFailed(code: positionError.rawValue))
            }
        } else {
            notes.append(AppStrings.maximizePositionNotSettable)
        }

        let sizeError = AXHelpers.set(size: destinationFrame.size, on: context.windowElement)
        guard sizeError == .success else {
            notes.append(AppStrings.maximizeSizeSetFailed(code: sizeError.rawValue))
            diagnostics.logMessage("Deterministic maximize failed for \(context.windowIdentifier): \(notes.joined(separator: " "))")
            return MaximizeResult(succeeded: false, appliedRect: nil, restored: shouldRestore, positionApplied: positionApplied, postApplyFrame: AXHelpers.cgRect(of: context.windowElement), notes: notes)
        }

        let postApplyFrame = AXHelpers.pollWindowFrame(of: context.windowElement)
        if let postApplyFrame, !Self.framesNearlyEqual(postApplyFrame, destinationFrame) {
            notes.append(AppStrings.maximizePostApplyFrameDiffers)
        }

        if shouldRestore {
            frameStore.removeStoredFrame(for: context.windowIdentifier)
            notes.append(AppStrings.maximizeRestoredPreviousFrame)
            if restoreResolution?.wasClamped == true {
                notes.append(AppStrings.maximizeRestoreClampedToVisibleFrame)
            } else {
                notes.append(AppStrings.maximizeRestoreExactFrame)
            }
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

    func isCurrentlyManagedMaximized(_ context: ClickedWindowContext) -> Bool {
        guard let currentFrame = context.windowFrame,
              let storedState = frameStore.storedState(for: context.windowIdentifier),
              storedState.lastManagedMaximizeFrame != nil else {
            return false
        }

        let screens = screenProvider()
        guard let chosenScreen = ScreenHelpers.bestScreen(for: currentFrame, screens: screens) else {
            return false
        }

        let targetFrame = ScreenHelpers.accessibilityRect(forVisibleFrame: chosenScreen.visibleFrame, in: screens)
        return Self.shouldRestore(currentFrame: currentFrame, targetFrame: targetFrame, storedState: storedState)
    }

    func performDragRestore(on context: ClickedWindowContext, cursorLocation: CGPoint) -> DragRestoreResult {
        guard let currentFrame = context.windowFrame else {
            return DragRestoreResult(restored: false, appliedRect: nil, notes: [AppStrings.maximizeWindowFrameUnavailable])
        }
        guard context.canSetSize, context.canSetPosition else {
            return DragRestoreResult(restored: false, appliedRect: nil, notes: [AppStrings.maximizeWindowSizeNotSettable])
        }
        guard let storedState = frameStore.storedState(for: context.windowIdentifier) else {
            return DragRestoreResult(restored: false, appliedRect: nil, notes: [AppStrings.titleBarDragRestoreSkipped])
        }

        guard let maximizeFrame = storedState.lastManagedMaximizeFrame,
              Self.framesNearlyEqual(currentFrame, maximizeFrame) else {
            return DragRestoreResult(restored: false, appliedRect: nil, notes: [AppStrings.titleBarDragRestoreSkipped])
        }

        let screens = screenProvider()
        guard let restoreResolution = Self.resolvedRestoreFrame(
            currentFrame: currentFrame,
            storedState: storedState,
            screens: screens,
            cursorLocation: cursorLocation
        ) else {
            return DragRestoreResult(restored: false, appliedRect: nil, notes: [AppStrings.maximizeTargetDisplayUnavailable])
        }
        let restoreFrame = restoreResolution.frame

        let positionError = AXHelpers.set(position: restoreFrame.origin, on: context.windowElement)
        let sizeError = AXHelpers.set(size: restoreFrame.size, on: context.windowElement)
        guard positionError == .success, sizeError == .success else {
            var notes: [String] = []
            if positionError != .success {
                notes.append(AppStrings.maximizePositionSetFailed(code: positionError.rawValue))
            }
            if sizeError != .success {
                notes.append(AppStrings.maximizeSizeSetFailed(code: sizeError.rawValue))
            }
            return DragRestoreResult(restored: false, appliedRect: nil, notes: notes)
        }

        frameStore.removeStoredFrame(for: context.windowIdentifier)
        diagnostics.logMessage(AppStrings.titleBarDragRestoreTriggered)
        var notes = [AppStrings.maximizeRestoredPreviousFrame]
        if restoreResolution.wasClamped {
            notes.append(AppStrings.maximizeRestoreClampedToVisibleFrame)
        } else {
            notes.append(AppStrings.maximizeRestoreExactFrame)
        }
        return DragRestoreResult(restored: true, appliedRect: restoreFrame, notes: notes)
    }

    static func targetRect(for windowFrame: CGRect, screens: [ScreenDescriptor]) -> CGRect? {
        ScreenHelpers.maximizeRect(for: windowFrame, screens: screens)
    }

    static func shouldRestore(currentFrame: CGRect, targetFrame: CGRect, storedState: StoredWindowFrameState?) -> Bool {
        guard let storedState else {
            return false
        }

        if let lastAppliedMaximizeFrame = storedState.lastManagedMaximizeFrame {
            let nearMaximizedState = framesNearlyEqual(currentFrame, lastAppliedMaximizeFrame) ||
                framesNearlyEqual(currentFrame, targetFrame)
            return nearMaximizedState && !framesNearlyEqual(storedState.restoreFrame, currentFrame)
        }

        return framesNearlyEqual(currentFrame, targetFrame) && !framesNearlyEqual(storedState.restoreFrame, targetFrame)
    }

    static func dragRestoreFrame(currentFrame: CGRect, restoreFrame: CGRect, cursorLocation: CGPoint) -> CGRect {
        var destination = CGRect(
            x: currentFrame.minX,
            y: currentFrame.minY,
            width: restoreFrame.width,
            height: restoreFrame.height
        )

        if !destination.contains(cursorLocation) {
            destination.origin.x = currentFrame.maxX - destination.width
        }

        if !destination.contains(cursorLocation) {
            destination.origin.x = cursorLocation.x - (destination.width / 2)
        }

        return destination.integral
    }

    static func resolvedRestoreFrame(
        currentFrame: CGRect,
        storedState: StoredWindowFrameState,
        screens: [ScreenDescriptor],
        cursorLocation: CGPoint? = nil
    ) -> RestoreFrameResolution? {
        guard let restoreScreen = restoreScreen(
            currentFrame: currentFrame,
            storedState: storedState,
            screens: screens
        ) else {
            return nil
        }

        let proposedFrame: CGRect
        if let cursorLocation {
            proposedFrame = dragRestoreFrame(
                currentFrame: currentFrame,
                restoreFrame: storedState.restoreFrame,
                cursorLocation: cursorLocation
            )
        } else {
            proposedFrame = storedState.restoreFrame.integral
        }

        let visibleFrame = ScreenHelpers.accessibilityRect(forVisibleFrame: restoreScreen.visibleFrame, in: screens)
        let clampedFrame = clampedRestoreFrame(proposedFrame, within: visibleFrame)
        return RestoreFrameResolution(
            frame: clampedFrame,
            wasClamped: !framesNearlyEqual(proposedFrame, clampedFrame, tolerance: 1)
        )
    }

    static func clampedRestoreFrame(_ restoreFrame: CGRect, within visibleFrame: CGRect) -> CGRect {
        let clampedSize = CGSize(
            width: min(restoreFrame.width, visibleFrame.width),
            height: min(restoreFrame.height, visibleFrame.height)
        )
        let maxX = visibleFrame.maxX - clampedSize.width
        let maxY = visibleFrame.maxY - clampedSize.height
        let clampedOrigin = CGPoint(
            x: min(max(restoreFrame.minX, visibleFrame.minX), maxX),
            y: min(max(restoreFrame.minY, visibleFrame.minY), maxY)
        )
        return CGRect(origin: clampedOrigin, size: clampedSize).integral
    }

    private static func restoreScreen(
        currentFrame: CGRect,
        storedState: StoredWindowFrameState,
        screens: [ScreenDescriptor]
    ) -> ScreenDescriptor? {
        if let originalScreen = bestIntersectingScreen(for: storedState.restoreFrame, screens: screens) {
            return originalScreen
        }
        if let maximizeFrame = storedState.lastManagedMaximizeFrame,
           let maximizeScreen = ScreenHelpers.bestScreen(for: maximizeFrame, screens: screens) {
            return maximizeScreen
        }
        return ScreenHelpers.bestScreen(for: currentFrame, screens: screens)
    }

    private static func bestIntersectingScreen(for frame: CGRect, screens: [ScreenDescriptor]) -> ScreenDescriptor? {
        screens
            .map { screen in
                (screen: screen, area: intersectionArea(frame, screen.frame))
            }
            .filter { $0.area > 0 }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .screen
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }

    static func framesNearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }
}
