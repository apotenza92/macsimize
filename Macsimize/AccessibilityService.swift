import AppKit
import ApplicationServices
import Foundation

final class AccessibilityService {
    private let diagnostics: DebugDiagnostics
    private let supportedGreenButtonSubroles: Set<String> = ["AXZoomButton", "AXFullScreenButton"]
    private let greenButtonHitTolerance: CGFloat = 8
    private let trafficLightHotZoneWidth: CGFloat = 180
    private let trafficLightHotZoneHeight: CGFloat = 64
    private let trafficLightHotZoneInset: CGFloat = 10
    private let maxAncestorTraversalDepth = 10

    init(diagnostics: DebugDiagnostics) {
        self.diagnostics = diagnostics
    }

    func resolveGreenButtonClick(at location: CGPoint) -> ClickedWindowContext? {
        if isLikelyInMenuBar(location) {
            return nil
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            diagnostics.logMessage("AX hit-test skipped: no frontmost app.")
            return nil
        }

        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            diagnostics.logMessage("AX hit-test skipped for Macsimize itself.")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let candidatePoints = candidateHitTestPoints(for: location)
        for candidatePoint in candidatePoints {
            var hitElement: AXUIElement?
            let hitError = AXUIElementCopyElementAtPosition(appElement, Float(candidatePoint.x), Float(candidatePoint.y), &hitElement)
            guard hitError == .success, let hitElement else {
                continue
            }

            if let buttonElement = resolveGreenButton(from: hitElement, clickLocation: candidatePoint) {
                if candidatePoint != location {
                    diagnostics.logMessage("AX hit-test succeeded using flipped screen coordinates.")
                }
                return context(for: buttonElement, app: app, clickLocation: location)
            }
        }

        for candidatePoint in candidatePoints {
            if let resolved = resolveUsingFocusedWindowButtonLookup(
                app: app,
                appElement: appElement,
                candidatePoint: candidatePoint,
                originalLocation: location
            ) {
                if candidatePoint != location {
                    diagnostics.logMessage("AX window-button lookup succeeded using flipped screen coordinates.")
                } else {
                    diagnostics.logMessage("AX window-button lookup succeeded after hit-test fallback.")
                }
                return resolved
            }
        }

        diagnostics.logMessage("AX hit-test failed for pid=\(app.processIdentifier) at \(NSStringFromPoint(location)).")
        return nil
    }

    func captureFrontmostWindowSnapshot() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            diagnostics.logMessage("Diagnostics snapshot skipped: no frontmost app.", forceVisible: true)
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = AXHelpers.elementAttribute(kAXFocusedWindowAttribute as String, on: appElement)
            ?? AXHelpers.elementAttribute(kAXMainWindowAttribute as String, on: appElement)

        guard let window = focusedWindow else {
            diagnostics.logMessage("Diagnostics snapshot: no focused window for \(app.localizedName ?? "Unknown").", forceVisible: true)
            return
        }

        let title = AXHelpers.stringAttribute(kAXTitleAttribute as String, on: window) ?? "Untitled"
        let frame = AXHelpers.cgRect(of: window)
        let canSetPosition = AXHelpers.isAttributeSettable(kAXPositionAttribute as String, on: window)
        let canSetSize = AXHelpers.isAttributeSettable(kAXSizeAttribute as String, on: window)
        let resizable = AXHelpers.boolAttribute("AXResizable", on: window) ?? canSetSize
        let isMainWindow = AXHelpers.boolAttribute(kAXMainAttribute as String, on: window) ?? false
        let isFocusedWindow = AXHelpers.boolAttribute(kAXFocusedAttribute as String, on: window) ?? false
        diagnostics.logMessage(
            "Frontmost window snapshot app=\(app.localizedName ?? "Unknown") bundle=\(app.bundleIdentifier ?? "-") title=\(title) frame=\(frame.map { NSStringFromRect($0) } ?? "-") resizable=\(resizable) focused=\(isFocusedWindow) main=\(isMainWindow) settable(position=\(canSetPosition), size=\(canSetSize))",
            forceVisible: true
        )
    }

    static func bestFrameMatchIndex(for point: CGPoint, candidateFrames: [CGRect], tolerance: CGFloat = 8) -> Int? {
        candidateFrames.enumerated()
            .filter { _, frame in
                frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            .min { lhs, rhs in
                squaredDistance(from: point, to: lhs.element) < squaredDistance(from: point, to: rhs.element)
            }?
            .offset
    }

    static func trafficLightHotZone(
        for windowFrame: CGRect,
        width: CGFloat = 180,
        height: CGFloat = 64,
        inset: CGFloat = 10
    ) -> CGRect {
        CGRect(
            x: windowFrame.minX - inset,
            y: windowFrame.maxY - height - inset,
            width: width + (inset * 2),
            height: height + (inset * 2)
        )
    }

    private func candidateHitTestPoints(for location: CGPoint) -> [CGPoint] {
        var candidates = [location]
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return candidates
        }

        let localY = location.y - screen.frame.minY
        let flipped = CGPoint(x: location.x, y: screen.frame.maxY - localY)
        if abs(flipped.y - location.y) > 1 {
            candidates.append(flipped)
        }
        return candidates
    }

    private func isLikelyInMenuBar(_ location: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return false
        }

        // Menu bar area is above visibleFrame on macOS screens.
        return location.y > screen.visibleFrame.maxY
    }

    private func resolveUsingFocusedWindowButtonLookup(
        app: NSRunningApplication,
        appElement: AXUIElement,
        candidatePoint: CGPoint,
        originalLocation: CGPoint
    ) -> ClickedWindowContext? {
        for window in focusedOrMainWindows(in: appElement) {
            guard let windowFrame = AXHelpers.cgRect(of: window) else {
                continue
            }
            let hotZone = Self.trafficLightHotZone(
                for: windowFrame,
                width: trafficLightHotZoneWidth,
                height: trafficLightHotZoneHeight,
                inset: trafficLightHotZoneInset
            )
            if !hotZone.contains(candidatePoint) {
                continue
            }

            guard let buttonElement = matchingGreenButton(in: window, clickLocation: candidatePoint) else {
                continue
            }

            return context(for: buttonElement, app: app, clickLocation: originalLocation)
        }

        return nil
    }

    private func resolveGreenButton(from hitElement: AXUIElement, clickLocation: CGPoint) -> AXUIElement? {
        if let directMatch = nearestGreenButton(from: hitElement) {
            return directMatch
        }

        guard let window = AXHelpers.window(of: hitElement) else {
            return nil
        }

        if let windowFrame = AXHelpers.cgRect(of: window) {
            let hotZone = Self.trafficLightHotZone(
                for: windowFrame,
                width: trafficLightHotZoneWidth,
                height: trafficLightHotZoneHeight,
                inset: trafficLightHotZoneInset
            )
            if !hotZone.contains(clickLocation) {
                return nil
            }
        }

        return matchingGreenButton(in: window, clickLocation: clickLocation)
    }

    private func matchingGreenButton(in window: AXUIElement, clickLocation: CGPoint) -> AXUIElement? {
        let buttons = greenButtonCandidates(in: window)
        let frameMatches: [(Int, CGRect)] = buttons.enumerated().compactMap { index, button in
            guard let frame = AXHelpers.cgRect(of: button) else {
                return nil
            }
            return (index, frame)
        }

        guard let matchedFrameIndex = Self.bestFrameMatchIndex(
            for: clickLocation,
            candidateFrames: frameMatches.map { $0.1 },
            tolerance: greenButtonHitTolerance
        ) else {
            return nil
        }

        return buttons[frameMatches[matchedFrameIndex].0]
    }

    private func greenButtonCandidates(in window: AXUIElement) -> [AXUIElement] {
        var results: [AXUIElement] = []
        var seen = Set<Int>()

        func appendCandidate(_ element: AXUIElement) {
            let identifier = Int(CFHash(element))
            guard seen.insert(identifier).inserted else {
                return
            }
            results.append(element)
        }

        for attribute in [kAXFullScreenButtonAttribute as String, kAXZoomButtonAttribute as String] {
            if let element = AXHelpers.elementAttribute(attribute, on: window) {
                appendCandidate(element)
            }
        }

        // Some apps do not expose AXZoomButton/AXFullScreenButton directly on the window.
        // In that case, do a bounded tree walk instead of an unbounded traversal.
        if results.isEmpty {
            var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
            var enqueued = Set([Int(CFHash(window))])
            var visited = 0
            let maxDepth = 4
            let maxVisitedNodes = 120

            while !queue.isEmpty, visited < maxVisitedNodes {
                let current = queue.removeFirst()
                visited += 1

                let role = AXHelpers.stringAttribute(kAXRoleAttribute as String, on: current.element)
                let subrole = AXHelpers.stringAttribute(kAXSubroleAttribute as String, on: current.element)
                if role == (kAXButtonRole as String), supportedGreenButtonSubroles.contains(subrole ?? "") {
                    appendCandidate(current.element)
                }

                guard current.depth < maxDepth else {
                    continue
                }

                let children = AXHelpers.children(of: current.element)
                let visibleChildren = AXHelpers.children(of: current.element, attribute: kAXVisibleChildrenAttribute as String)
                for child in visibleChildren + children {
                    let identifier = Int(CFHash(child))
                    if enqueued.contains(identifier) {
                        continue
                    }
                    enqueued.insert(identifier)
                    queue.append((child, current.depth + 1))
                }
            }
        }

        return results
    }

    private func focusedOrMainWindows(in appElement: AXUIElement) -> [AXUIElement] {
        var windows: [AXUIElement] = []
        var seen = Set<Int>()

        func appendWindow(_ window: AXUIElement?) {
            guard let window else {
                return
            }
            let identifier = Int(CFHash(window))
            guard seen.insert(identifier).inserted else {
                return
            }
            windows.append(window)
        }

        appendWindow(AXHelpers.elementAttribute(kAXFocusedWindowAttribute as String, on: appElement))
        appendWindow(AXHelpers.elementAttribute(kAXMainWindowAttribute as String, on: appElement))

        return windows
    }

    private func nearestGreenButton(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var remainingDepth = maxAncestorTraversalDepth
        while let candidate = current, remainingDepth > 0 {
            let role = AXHelpers.stringAttribute(kAXRoleAttribute as String, on: candidate)
            let subrole = AXHelpers.stringAttribute(kAXSubroleAttribute as String, on: candidate)
            if role == (kAXButtonRole as String), supportedGreenButtonSubroles.contains(subrole ?? "") {
                return candidate
            }
            current = AXHelpers.parent(of: candidate)
            remainingDepth -= 1
        }
        return nil
    }

    private func context(for buttonElement: AXUIElement, app: NSRunningApplication, clickLocation: CGPoint) -> ClickedWindowContext? {
        guard let windowElement = AXHelpers.window(of: buttonElement) else {
            diagnostics.logMessage("AX hit-test found green button but no parent window for pid=\(app.processIdentifier).")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = AXHelpers.elementAttribute(kAXFocusedWindowAttribute as String, on: appElement)
        let mainWindow = AXHelpers.elementAttribute(kAXMainWindowAttribute as String, on: appElement)
        let windowTitle = AXHelpers.stringAttribute(kAXTitleAttribute as String, on: windowElement)
        let windowFrame = AXHelpers.cgRect(of: windowElement)
        let canSetPosition = AXHelpers.isAttributeSettable(kAXPositionAttribute as String, on: windowElement)
        let canSetSize = AXHelpers.isAttributeSettable(kAXSizeAttribute as String, on: windowElement)
        let resizable = AXHelpers.boolAttribute("AXResizable", on: windowElement) ?? canSetSize
        let actions = AXHelpers.actions(for: buttonElement)
        let role = AXHelpers.stringAttribute(kAXRoleAttribute as String, on: buttonElement)
        let subrole = AXHelpers.stringAttribute(kAXSubroleAttribute as String, on: buttonElement)
        let windowNumber = AXHelpers.windowNumber(of: windowElement)
        let identifier = makeWindowIdentifier(pid: app.processIdentifier, windowNumber: windowNumber, title: windowTitle)
        let isMainWindow = AXHelpers.boolAttribute(kAXMainAttribute as String, on: windowElement)
            ?? AXHelpers.elementsEqual(windowElement, mainWindow)
        let isFocusedWindow = AXHelpers.boolAttribute(kAXFocusedAttribute as String, on: windowElement)
            ?? AXHelpers.elementsEqual(windowElement, focusedWindow)

        return ClickedWindowContext(
            appName: app.localizedName ?? "Unknown App",
            bundleIdentifier: app.bundleIdentifier,
            pid: app.processIdentifier,
            clickLocation: clickLocation,
            buttonElement: buttonElement,
            windowElement: windowElement,
            windowIdentifier: identifier,
            windowNumber: windowNumber,
            windowTitle: windowTitle,
            elementRole: role,
            elementSubrole: subrole,
            availableActions: actions,
            windowFrame: windowFrame,
            canSetPosition: canSetPosition,
            canSetSize: canSetSize,
            isResizable: resizable,
            isMainWindow: isMainWindow,
            isFocusedWindow: isFocusedWindow
        )
    }

    private func makeWindowIdentifier(pid: pid_t, windowNumber: Int?, title: String?) -> String {
        if let windowNumber {
            return "pid:\(pid)-window:\(windowNumber)"
        }

        if let title, !title.isEmpty {
            return "pid:\(pid)-title:\(title)"
        }

        return "pid:\(pid)-window:unknown"
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return (dx * dx) + (dy * dy)
    }
}
