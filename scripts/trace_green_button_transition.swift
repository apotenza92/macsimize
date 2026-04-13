#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

struct FrameSample: Codable {
    let elapsedMilliseconds: Int
    let frame: String
}

struct TraceResult: Codable {
    let appName: String
    let windowFrameBeforeClick: String
    let expectedMaximizedFrame: String
    let distinctFrames: [FrameSample]
    let finalFrame: String
    let reachedExpectedFrame: Bool
    let instantMaximizePass: Bool
    let failureReason: String?
}

let appName = CommandLine.arguments.dropFirst().first ?? "Brave Browser"
let sampleDurationSeconds = Double(ProcessInfo.processInfo.environment["MACSIMIZE_TRACE_DURATION_SECONDS"] ?? "2.4") ?? 2.4
let sampleIntervalSeconds = Double(ProcessInfo.processInfo.environment["MACSIMIZE_TRACE_INTERVAL_SECONDS"] ?? "0.016") ?? 0.016
let frameTolerance = CGFloat(Double(ProcessInfo.processInfo.environment["MACSIMIZE_TRACE_TOLERANCE"] ?? "8") ?? 8)

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("trace-helper: \(message)\n", stderr)
    exit(code)
}

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    guard result == .success else {
        return nil
    }
    return value
}

func elementAttr(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attr(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeBitCast(value, to: AXUIElement.self)
}

func pointAttr(_ element: AXUIElement, _ key: String) -> CGPoint? {
    guard let value = attr(element, key), CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}

func sizeAttr(_ element: AXUIElement, _ key: String) -> CGSize? {
    guard let value = attr(element, key), CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}

func rect(of element: AXUIElement) -> CGRect? {
    guard let origin = pointAttr(element, kAXPositionAttribute),
          let size = sizeAttr(element, kAXSizeAttribute) else {
        return nil
    }
    return CGRect(origin: origin, size: size)
}

func descendants(of element: AXUIElement) -> [AXUIElement] {
    let children = (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    return children + children.flatMap(descendants)
}

func preferredWindow(for appElement: AXUIElement) -> AXUIElement? {
    if let focusedWindow = elementAttr(appElement, kAXFocusedWindowAttribute) {
        return focusedWindow
    }

    if let mainWindow = elementAttr(appElement, kAXMainWindowAttribute) {
        return mainWindow
    }

    let windows = (attr(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    if let standardWindow = windows.first(where: { (attr($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole as String }) {
        return standardWindow
    }

    return windows.first
}

func greenButton(in window: AXUIElement) -> AXUIElement? {
    if let fullScreenButton = elementAttr(window, "AXFullScreenButton") {
        return fullScreenButton
    }

    if let zoomButton = elementAttr(window, kAXZoomButtonAttribute) {
        return zoomButton
    }

    return descendants(of: window).first {
        guard let subrole = attr($0, kAXSubroleAttribute) as? String else {
            return false
        }
        return subrole == "AXFullScreenButton" || subrole == (kAXZoomButtonSubrole as String)
    }
}

func waitForWindow(in appElement: AXUIElement, attempts: Int = 60, intervalMicroseconds: useconds_t = 100_000) -> AXUIElement? {
    for attempt in 0..<attempts {
        if let window = preferredWindow(for: appElement) {
            return window
        }

        if attempt < attempts - 1 {
            usleep(intervalMicroseconds)
        }
    }

    return nil
}

func waitForGreenButton(in window: AXUIElement, attempts: Int = 20, intervalMicroseconds: useconds_t = 50_000) -> AXUIElement? {
    for attempt in 0..<attempts {
        if let button = greenButton(in: window) {
            return button
        }

        if attempt < attempts - 1 {
            usleep(intervalMicroseconds)
        }
    }

    return nil
}

func fallbackWindowFrame(for appName: String) -> CGRect? {
    let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let matchingWindows = windowInfo.filter {
        ($0[kCGWindowOwnerName as String] as? String) == appName
            && (($0[kCGWindowLayer as String] as? Int) == 0)
    }

    let bestWindow = matchingWindows.max {
        let lhsBounds = ($0[kCGWindowBounds as String] as? [String: Any]) ?? [:]
        let rhsBounds = ($1[kCGWindowBounds as String] as? [String: Any]) ?? [:]
        let lhsArea = ((lhsBounds["Width"] as? Double) ?? 0) * ((lhsBounds["Height"] as? Double) ?? 0)
        let rhsArea = ((rhsBounds["Width"] as? Double) ?? 0) * ((rhsBounds["Height"] as? Double) ?? 0)
        return lhsArea < rhsArea
    }

    guard let bounds = bestWindow?[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Double,
          let y = bounds["Y"] as? Double,
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return nil
    }

    return CGRect(x: x, y: y, width: width, height: height)
}

func readWindowFrame(axWindow: AXUIElement?, appName: String) -> CGRect? {
    axWindow.flatMap(rect(of:)) ?? fallbackWindowFrame(for: appName)
}

func accessibilityRect(forScreenFrame screenFrame: CGRect, desktopTop: CGFloat) -> CGRect {
    CGRect(
        x: screenFrame.minX,
        y: desktopTop - screenFrame.maxY,
        width: screenFrame.width,
        height: screenFrame.height
    )
}

func accessibilityRect(forVisibleFrame visibleFrame: CGRect, desktopTop: CGFloat) -> CGRect {
    CGRect(
        x: visibleFrame.minX,
        y: desktopTop - visibleFrame.maxY,
        width: visibleFrame.width,
        height: visibleFrame.height
    )
}

func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else {
        return 0
    }
    return intersection.width * intersection.height
}

func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    let dx = lhs.x - rhs.x
    let dy = lhs.y - rhs.y
    return dx * dx + dy * dy
}

func expectedMaximizedFrame(for windowFrame: CGRect) -> CGRect? {
    let screens = NSScreen.screens
    let desktopTop = screens.map { $0.frame.maxY }.max() ?? 0

    let bestScreen = screens.max { lhs, rhs in
        let lhsRect = accessibilityRect(forScreenFrame: lhs.frame, desktopTop: desktopTop)
        let rhsRect = accessibilityRect(forScreenFrame: rhs.frame, desktopTop: desktopTop)
        let lhsArea = intersectionArea(windowFrame, lhsRect)
        let rhsArea = intersectionArea(windowFrame, rhsRect)
        if lhsArea == rhsArea {
            let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
            let lhsDistance = distanceSquared(center, CGPoint(x: lhsRect.midX, y: lhsRect.midY))
            let rhsDistance = distanceSquared(center, CGPoint(x: rhsRect.midX, y: rhsRect.midY))
            return lhsDistance > rhsDistance
        }
        return lhsArea < rhsArea
    } ?? NSScreen.main

    guard let screen = bestScreen else {
        return nil
    }

    return accessibilityRect(forVisibleFrame: screen.visibleFrame, desktopTop: desktopTop).integral
}

func framesNearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance
        && abs(lhs.origin.y - rhs.origin.y) <= tolerance
        && abs(lhs.width - rhs.width) <= tolerance
        && abs(lhs.height - rhs.height) <= tolerance
}

func clickPoint(windowRect: CGRect, buttonRect: CGRect?) -> CGPoint {
    var rect = buttonRect ?? CGRect(x: windowRect.minX + 54, y: windowRect.minY + 9, width: 16, height: 16)
    if rect.origin.x < windowRect.origin.x || rect.origin.y < windowRect.origin.y {
        rect.origin.x += windowRect.origin.x
        rect.origin.y += windowRect.origin.y
    }
    return CGPoint(x: rect.midX, y: rect.midY)
}

func postClick(at point: CGPoint) {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        fail("failed to create click events", code: 4)
    }

    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
}

func stringify(_ rect: CGRect) -> String {
    let integral = rect.integral
    return NSStringFromRect(integral)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    fail("app not running: \(appName)", code: 10)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
app.activate(options: [.activateAllWindows])
usleep(1_000_000)

guard let axWindow = waitForWindow(in: appElement) else {
    fail("no accessible window for app: \(appName)", code: 11)
}

guard let initialFrame = readWindowFrame(axWindow: axWindow, appName: appName) else {
    fail("could not read initial window frame for app: \(appName)", code: 12)
}

guard let expectedFrame = expectedMaximizedFrame(for: initialFrame) else {
    fail("could not determine expected maximized frame", code: 13)
}

let buttonRect = waitForGreenButton(in: axWindow).flatMap(rect(of:))
let point = clickPoint(windowRect: initialFrame, buttonRect: buttonRect)

var distinctFrames: [FrameSample] = [
    FrameSample(elapsedMilliseconds: 0, frame: stringify(initialFrame))
]
var lastDistinctFrame = initialFrame

postClick(at: point)
let start = CFAbsoluteTimeGetCurrent()
let deadline = start + sampleDurationSeconds

while CFAbsoluteTimeGetCurrent() <= deadline {
    if let frame = readWindowFrame(axWindow: axWindow, appName: appName), !framesNearlyEqual(frame, lastDistinctFrame, tolerance: frameTolerance) {
        let elapsedMilliseconds = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
        distinctFrames.append(FrameSample(elapsedMilliseconds: elapsedMilliseconds, frame: stringify(frame)))
        lastDistinctFrame = frame
    }
    Thread.sleep(forTimeInterval: sampleIntervalSeconds)
}

guard let finalFrame = readWindowFrame(axWindow: axWindow, appName: appName) else {
    fail("could not read final window frame", code: 14)
}

let reachedExpectedFrame = framesNearlyEqual(finalFrame, expectedFrame, tolerance: frameTolerance)
let instantMaximizePass = reachedExpectedFrame && distinctFrames.count <= 2
let failureReason: String?
if !reachedExpectedFrame {
    failureReason = "final frame did not match expected maximized bounds"
} else if distinctFrames.count > 2 {
    failureReason = "observed intermediate frames before the final maximized frame"
} else {
    failureReason = nil
}

let result = TraceResult(
    appName: appName,
    windowFrameBeforeClick: stringify(initialFrame),
    expectedMaximizedFrame: stringify(expectedFrame),
    distinctFrames: distinctFrames,
    finalFrame: stringify(finalFrame),
    reachedExpectedFrame: reachedExpectedFrame,
    instantMaximizePass: instantMaximizePass,
    failureReason: failureReason
)

let data = try encoder.encode(result)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(instantMaximizePass ? 0 : 20)
