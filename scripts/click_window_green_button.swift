import ApplicationServices
import AppKit
import Foundation

let appName = CommandLine.arguments.dropFirst().first ?? "TextEdit"

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    guard result == .success else {
        return nil
    }
    return value
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

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    fputs("app not running: \(appName)\n", stderr)
    exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
guard let window = ((attr(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first else {
    fputs("no window for app: \(appName)\n", stderr)
    exit(2)
}

let greenButtons = descendants(of: window).filter {
    guard let subrole = attr($0, kAXSubroleAttribute) as? String else {
        return false
    }
    return subrole == "AXFullScreenButton" || subrole == (kAXZoomButtonSubrole as String)
}

guard let greenButton = greenButtons.first, let buttonRect = rect(of: greenButton) else {
    fputs("no green button found for app: \(appName)\n", stderr)
    exit(3)
}

let clickPoint = CGPoint(x: buttonRect.midX, y: buttonRect.midY)
guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
      let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) else {
    fputs("failed to create mouse events\n", stderr)
    exit(4)
}

down.post(tap: .cghidEventTap)
usleep(40_000)
up.post(tap: .cghidEventTap)
