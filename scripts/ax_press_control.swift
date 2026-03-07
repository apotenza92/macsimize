import ApplicationServices
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: ax_press_control.swift <process-name> <role> <label>\n", stderr)
    exit(64)
}

let processName = CommandLine.arguments[1]
let targetRole = CommandLine.arguments[2]
let targetLabel = CommandLine.arguments[3]

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    guard result == .success else {
        return nil
    }
    return value
}

func descendants(of element: AXUIElement) -> [AXUIElement] {
    let children = (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    return children + children.flatMap(descendants)
}

func elementLabel(_ element: AXUIElement) -> String {
    if let title = attr(element, kAXTitleAttribute) as? String, !title.isEmpty {
        return title
    }
    if let description = attr(element, kAXDescriptionAttribute) as? String, !description.isEmpty {
        return description
    }
    if let value = attr(element, kAXValueAttribute) as? String, !value.isEmpty {
        return value
    }
    return ""
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == processName }) else {
    exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
guard let windows = attr(appElement, kAXWindowsAttribute) as? [AXUIElement], let window = windows.first else {
    exit(2)
}

let candidates = descendants(of: window).filter {
    (attr($0, kAXRoleAttribute) as? String) == targetRole
}

for candidate in candidates where elementLabel(candidate) == targetLabel {
    let result = AXUIElementPerformAction(candidate, kAXPressAction as CFString)
    if result == .success {
        exit(0)
    }
    exit(3)
}

exit(4)
