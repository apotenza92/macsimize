import ApplicationServices
import AppKit
import Foundation

let appName = CommandLine.arguments.dropFirst().first ?? "TextEdit"
let debugLoggingEnabled = ProcessInfo.processInfo.environment["MACSIMIZE_CLICK_DEBUG"] == "1"

func debugLog(_ message: String) {
    guard debugLoggingEnabled else {
        return
    }
    fputs("[click-helper] \(message)\n", stderr)
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

func waitForWindow(in appElement: AXUIElement, attempts: Int = 20, intervalMicroseconds: useconds_t = 100_000) -> AXUIElement? {
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

func waitForFallbackWindowFrame(
    for appName: String,
    attempts: Int = 20,
    intervalMicroseconds: useconds_t = 100_000
) -> CGRect? {
    for attempt in 0..<attempts {
        if let frame = fallbackWindowFrame(for: appName) {
            return frame
        }

        if attempt < attempts - 1 {
            usleep(intervalMicroseconds)
        }
    }

    return nil
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    fputs("app not running: \(appName)\n", stderr)
    exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
debugLog("app pid=\(app.processIdentifier)")
app.activate(options: [.activateAllWindows])

let axWindow = waitForWindow(in: appElement)
let windowRect = axWindow.flatMap(rect(of:)) ?? waitForFallbackWindowFrame(for: appName)

guard let windowRect else {
    fputs("no window for app: \(appName)\n", stderr)
    exit(2)
}
debugLog("windowRect=\(windowRect)")

var buttonRect: CGRect?
if let axWindow, let greenButton = waitForGreenButton(in: axWindow) {
    buttonRect = rect(of: greenButton)
}

if buttonRect == nil {
    // Fallback to the standard macOS traffic-light layout within the window frame.
    buttonRect = CGRect(x: windowRect.minX + 54, y: windowRect.minY + 9, width: 16, height: 16)
}

guard var buttonRect else {
    fputs("no green button found for app: \(appName)\n", stderr)
    exit(3)
}
debugLog("buttonRect(raw)=\(buttonRect)")

// AX button coordinates can be window-local or screen-relative depending on
// the window type, so only offset values that are clearly local to the window.
if buttonRect.origin.x < windowRect.origin.x || buttonRect.origin.y < windowRect.origin.y {
    buttonRect.origin.x += windowRect.origin.x
    buttonRect.origin.y += windowRect.origin.y
}
debugLog("buttonRect(normalized)=\(buttonRect)")

let clickPoint = CGPoint(x: buttonRect.midX, y: buttonRect.midY)
debugLog("clickPoint=\(clickPoint)")
guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else {
    fputs("failed to create mouse events\n", stderr)
    exit(4)
}

down.post(tap: .cghidEventTap)
usleep(40_000)
up.post(tap: .cghidEventTap)
debugLog("posted down/up")
