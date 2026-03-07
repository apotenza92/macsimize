import AppKit
import ApplicationServices
import Foundation

final class AccessibilityService {
    private let diagnostics: DebugDiagnostics
    private let supportedGreenButtonSubroles: Set<String> = ["AXZoomButton", "AXFullScreenButton"]
    private let greenButtonHitTolerance: CGFloat = 8

    init(diagnostics: DebugDiagnostics) {
        self.diagnostics = diagnostics
    }

    func resolveGreenButtonClick(at location: CGPoint, excludedBundleIDs: Set<String>) -> ClickedWindowContext? {
        for candidatePoint in candidateHitTestPoints(for: location) {
            if let resolved = resolveUsingSystemWideHitTest(at: candidatePoint, originalLocation: location, excludedBundleIDs: excludedBundleIDs) {
                if candidatePoint != location {
                    diagnostics.logMessage("AX hit-test succeeded using flipped screen coordinates.")
                }
                return resolved
            }
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            diagnostics.logMessage("AX hit-test skipped: no frontmost app.")
            return nil
        }

        if let bundleIdentifier = app.bundleIdentifier, excludedBundleIDs.contains(bundleIdentifier) {
            diagnostics.logMessage("AX hit-test skipped for excluded app \(bundleIdentifier).")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        for candidatePoint in candidateHitTestPoints(for: location) {
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

        for candidatePoint in candidateHitTestPoints(for: location) {
            if let resolved = resolveUsingWindowButtonLookup(app: app, candidatePoint: candidatePoint, originalLocation: location) {
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

    private func resolveUsingSystemWideHitTest(at location: CGPoint, originalLocation: CGPoint, excludedBundleIDs: Set<String>) -> ClickedWindowContext? {
        let systemWide = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        let hitError = AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &hitElement)
        guard hitError == .success, let hitElement else {
            return nil
        }

        guard let pid = pid(of: hitElement),
              let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        if let bundleIdentifier = app.bundleIdentifier, excludedBundleIDs.contains(bundleIdentifier) {
            diagnostics.logMessage("AX system-wide hit-test skipped for excluded app \(bundleIdentifier).")
            return nil
        }

        guard let buttonElement = resolveGreenButton(from: hitElement, clickLocation: location) else {
            return nil
        }

        return context(for: buttonElement, app: app, clickLocation: originalLocation)
    }

    private func resolveUsingWindowButtonLookup(app: NSRunningApplication, candidatePoint: CGPoint, originalLocation: CGPoint) -> ClickedWindowContext? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        for window in candidateWindows(in: appElement) {
            if let windowFrame = AXHelpers.cgRect(of: window),
               !windowFrame.insetBy(dx: -greenButtonHitTolerance, dy: -greenButtonHitTolerance).contains(candidatePoint) {
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

        var stack = [window]
        while let element = stack.popLast() {
            let role = AXHelpers.stringAttribute(kAXRoleAttribute as String, on: element)
            let subrole = AXHelpers.stringAttribute(kAXSubroleAttribute as String, on: element)
            if role == (kAXButtonRole as String), supportedGreenButtonSubroles.contains(subrole ?? "") {
                appendCandidate(element)
            }

            let children = AXHelpers.children(of: element)
            let visibleChildren = AXHelpers.children(of: element, attribute: kAXVisibleChildrenAttribute as String)
            stack.append(contentsOf: visibleChildren.reversed())
            stack.append(contentsOf: children.reversed())
        }

        return results
    }

    private func candidateWindows(in appElement: AXUIElement) -> [AXUIElement] {
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
        for window in AXHelpers.children(of: appElement, attribute: kAXWindowsAttribute as String) {
            appendWindow(window)
        }

        return windows
    }

    private func nearestGreenButton(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        while let candidate = current {
            let role = AXHelpers.stringAttribute(kAXRoleAttribute as String, on: candidate)
            let subrole = AXHelpers.stringAttribute(kAXSubroleAttribute as String, on: candidate)
            if role == (kAXButtonRole as String), supportedGreenButtonSubroles.contains(subrole ?? "") {
                return candidate
            }
            current = AXHelpers.parent(of: candidate)
        }
        return nil
    }

    private func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else {
            return nil
        }
        return pid
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
