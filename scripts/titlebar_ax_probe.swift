#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

struct SampleSpec {
    let label: String
    let xFraction: CGFloat
    let yInset: CGFloat
}

struct SampleResult: Codable {
    let sampleLabel: String
    let screenX: Int
    let screenY: Int
    let hitRolePath: [String]
    let hitActionPath: [String]
    let hitFramePath: [String]
    let topContainerRole: String
    let containsAXToolbar: Bool
    let containsAXTabGroup: Bool
    let containsInteractiveControl: Bool
    let containsStaticText: Bool
    let containsDuplicateLeafGroup: Bool
    let structureClass: String
    let riskLevel: String
    let recommendedGUICheck: String
    let notes: String
}

struct ProbeResult: Codable {
    let appName: String
    let bundleID: String
    let family: String
    let priority: String
    let sampleProfile: String
    let status: String
    let windowFrame: String
    let samples: [SampleResult]
    let notes: String
}

struct ArgumentParser {
    private let values: [String: String]

    init(arguments: [String]) {
        var parsed: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                index += 1
                continue
            }
            let key = String(argument.dropFirst(2))
            let value: String
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                value = arguments[index + 1]
                index += 2
            } else {
                value = "true"
                index += 1
            }
            parsed[key] = value
        }
        self.values = parsed
    }

    func value(_ key: String, default defaultValue: String = "") -> String {
        values[key] ?? defaultValue
    }
}

func encodeAndExit(_ result: ProbeResult) -> Never {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! encoder.encode(result)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

func stringAttribute(_ attribute: String, on element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value as? String
}

func elementAttribute(_ attribute: String, on element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func pointAttribute(_ attribute: String, on element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

func sizeAttribute(_ attribute: String, on element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
}

func rect(of element: AXUIElement) -> CGRect? {
    guard let origin = pointAttribute(kAXPositionAttribute as String, on: element),
          let size = sizeAttribute(kAXSizeAttribute as String, on: element) else {
        return nil
    }
    return CGRect(origin: origin, size: size)
}

func actions(for element: AXUIElement) -> [String] {
    var actions: CFArray?
    guard AXUIElementCopyActionNames(element, &actions) == .success,
          let names = actions as? [String] else {
        return []
    }
    return names
}

func parent(of element: AXUIElement) -> AXUIElement? {
    elementAttribute(kAXParentAttribute as String, on: element)
}

func focusedOrMainWindow(for application: NSRunningApplication) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    if let focused = elementAttribute(kAXFocusedWindowAttribute as String, on: appElement) {
        return focused
    }
    if let main = elementAttribute(kAXMainWindowAttribute as String, on: appElement) {
        return main
    }
    return nil
}

func sampleSpecs(for profile: String) -> [SampleSpec] {
    switch profile {
    case "standard_titlebar":
        return [
            SampleSpec(label: "left_blank", xFraction: 0.22, yInset: 26),
            SampleSpec(label: "center_title", xFraction: 0.50, yInset: 26),
            SampleSpec(label: "right_titlebar", xFraction: 0.78, yInset: 26)
        ]
    case "unified_toolbar":
        return [
            SampleSpec(label: "left_drag_region", xFraction: 0.22, yInset: 26),
            SampleSpec(label: "center_passive", xFraction: 0.50, yInset: 26),
            SampleSpec(label: "control_probe", xFraction: 0.36, yInset: 26),
            SampleSpec(label: "right_passive", xFraction: 0.78, yInset: 26)
        ]
    case "browser_tabstrip":
        return [
            SampleSpec(label: "traffic_light_gap", xFraction: 0.18, yInset: 26),
            SampleSpec(label: "active_tab", xFraction: 0.22, yInset: 26),
            SampleSpec(label: "blank_tabstrip", xFraction: 0.50, yInset: 26),
            SampleSpec(label: "toolbar_control", xFraction: 0.36, yInset: 56),
            SampleSpec(label: "far_right_top_strip", xFraction: 0.78, yInset: 26)
        ]
    case "editor_custom_toolbar":
        return [
            SampleSpec(label: "left_top_strip", xFraction: 0.22, yInset: 26),
            SampleSpec(label: "center_command_region", xFraction: 0.50, yInset: 26),
            SampleSpec(label: "control_probe", xFraction: 0.60, yInset: 26),
            SampleSpec(label: "right_top_strip", xFraction: 0.78, yInset: 26)
        ]
    default:
        return [
            SampleSpec(label: "left_top_strip", xFraction: 0.22, yInset: 26),
            SampleSpec(label: "mid_top_strip", xFraction: 0.50, yInset: 26),
            SampleSpec(label: "right_top_strip", xFraction: 0.78, yInset: 26)
        ]
    }
}

func samplePoint(for spec: SampleSpec, in frame: CGRect) -> CGPoint {
    let x = frame.minX + (frame.width * spec.xFraction)
    let maximumInset = max(12, min(frame.height * 0.14, 72))
    let y = frame.minY + min(spec.yInset, maximumInset)
    return CGPoint(x: x, y: y)
}

func rolesAndAncestors(from element: AXUIElement, window: AXUIElement?) -> [(role: String, actions: [String], frame: CGRect?)] {
    var results: [(role: String, actions: [String], frame: CGRect?)] = []
    var current: AXUIElement? = element
    var remainingDepth = 8

    while let candidate = current, remainingDepth > 0 {
        let role = stringAttribute(kAXRoleAttribute as String, on: candidate) ?? "-"
        results.append((role: role, actions: actions(for: candidate), frame: rect(of: candidate)))
        if let window, CFEqual(candidate, window) {
            break
        }
        if role == kAXWindowRole as String {
            break
        }
        current = parent(of: candidate)
        remainingDepth -= 1
    }

    return results
}

func framesNearlyEqual(_ lhs: CGRect?, _ rhs: CGRect?, tolerance: CGFloat = 2) -> Bool {
    guard let lhs, let rhs else {
        return false
    }
    return abs(lhs.minX - rhs.minX) <= tolerance
        && abs(lhs.minY - rhs.minY) <= tolerance
        && abs(lhs.width - rhs.width) <= tolerance
        && abs(lhs.height - rhs.height) <= tolerance
}

func interactiveRole(_ role: String, actions: [String]) -> Bool {
    let interactiveRoles: Set<String> = [
        kAXButtonRole as String,
        kAXRadioButtonRole as String,
        kAXCheckBoxRole as String,
        kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String,
        kAXComboBoxRole as String,
        kAXTextFieldRole as String,
        "AXSearchField",
        kAXSliderRole as String,
        kAXIncrementorRole as String
    ]
    let passiveRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXImageRole as String,
        kAXGroupRole as String,
        "AXSplitGroup",
        kAXToolbarRole as String,
        kAXWindowRole as String,
        "AXTabGroup"
    ]
    let interactiveActions: Set<String> = [
        kAXPressAction as String,
        kAXConfirmAction as String,
        kAXIncrementAction as String,
        kAXDecrementAction as String
    ]

    if interactiveRoles.contains(role) {
        return true
    }
    if passiveRoles.contains(role) {
        return false
    }
    return !interactiveActions.isDisjoint(with: Set(actions))
}

func classify(sampleLabel: String, chain: [(role: String, actions: [String], frame: CGRect?)]) -> (String, String, String, String) {
    let roles = chain.map(\.role)
    let containsToolbar = roles.contains(kAXToolbarRole as String)
    let containsTabGroup = roles.contains("AXTabGroup")
    let containsStaticText = roles.contains(kAXStaticTextRole as String)
    let containsInteractive = chain.contains { interactiveRole($0.role, actions: $0.actions) }
    let duplicateLeafGroup = roles.count >= 2
        && roles[0] == kAXGroupRole as String
        && roles[1] == kAXGroupRole as String
        && framesNearlyEqual(chain[0].frame, chain[1].frame)

    let structureClass: String
    if containsTabGroup && duplicateLeafGroup {
        structureClass = "chromium_tab"
    } else if containsTabGroup && !containsInteractive {
        structureClass = "chromium_tabstrip_blank"
    } else if roles.first == kAXWindowRole as String {
        structureClass = "native_window"
    } else if roles.first == kAXStaticTextRole as String || (containsStaticText && roles.contains(kAXWindowRole as String)) {
        structureClass = "static_title_region"
    } else if containsToolbar && containsInteractive {
        structureClass = "toolbar_control"
    } else if containsToolbar {
        structureClass = "toolbar_passive"
    } else if roles.first == kAXGroupRole as String || roles.first == "AXSplitGroup" {
        structureClass = "unknown_container"
    } else {
        structureClass = "unsupported"
    }

    let riskLevel: String
    switch structureClass {
    case "native_window", "static_title_region", "toolbar_passive", "chromium_tabstrip_blank", "toolbar_control":
        riskLevel = roles.first == "AXSplitGroup" ? "medium" : "low"
    case "unknown_container":
        riskLevel = roles.first == "AXSplitGroup" ? "medium" : "high"
    default:
        riskLevel = "high"
    }

    let recommendedGUICheck: String
    switch structureClass {
    case "chromium_tab":
        recommendedGUICheck = "tab_should_not_maximize"
    case "chromium_tabstrip_blank":
        recommendedGUICheck = "blank_tabstrip_should_maximize"
    case "toolbar_control":
        recommendedGUICheck = "control_should_not_maximize"
    case "toolbar_passive", "static_title_region":
        recommendedGUICheck = "title_or_passive_region_should_maximize"
    case "native_window":
        recommendedGUICheck = "blank_region_should_maximize"
    case "unknown_container":
        recommendedGUICheck = containsInteractive ? "control_should_not_maximize" : "title_or_passive_region_should_maximize"
    default:
        recommendedGUICheck = ""
    }

    let note: String
    if sampleLabel == "control_probe" && !containsInteractive {
        note = "control probe did not hit an obvious interactive control"
    } else if structureClass == "unknown_container" {
        note = "unrecognized passive container in titlebar band"
    } else if structureClass == "unsupported" {
        note = "top chrome hit an unsupported role chain"
    } else {
        note = ""
    }

    return (structureClass, riskLevel, recommendedGUICheck, note)
}

let parser = ArgumentParser(arguments: CommandLine.arguments)
let appName = parser.value("app-name")
let bundleID = parser.value("bundle-id")
let family = parser.value("family", default: "unknown")
let priority = parser.value("priority", default: "P1")
let sampleProfile = parser.value("sample-profile", default: "unknown_top_chrome")

let application = NSWorkspace.shared.runningApplications.first {
    if !$0.isFinishedLaunching {
        return false
    }
    if $0.activationPolicy != .regular && $0.bundleIdentifier != bundleID {
        return false
    }
    if $0.bundleIdentifier != bundleID {
        return $0.localizedName == appName
    }
    return true
}

guard let application else {
    encodeAndExit(
        ProbeResult(
            appName: appName,
            bundleID: bundleID,
            family: family,
            priority: priority,
            sampleProfile: sampleProfile,
            status: "missing_app",
            windowFrame: "",
            samples: [],
            notes: "app is not running"
        )
    )
}

guard let window = focusedOrMainWindow(for: application),
      let windowFrame = rect(of: window) else {
    encodeAndExit(
        ProbeResult(
            appName: appName,
            bundleID: bundleID,
            family: family,
            priority: priority,
            sampleProfile: sampleProfile,
            status: "no_window",
            windowFrame: "",
            samples: [],
            notes: "front window was not accessible"
        )
    )
}

let systemWide = AXUIElementCreateSystemWide()
let samples = sampleSpecs(for: sampleProfile).map { spec -> SampleResult in
    let point = samplePoint(for: spec, in: windowFrame)
    var hitElement: AXUIElement?
    let hitError = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hitElement)
    guard hitError == .success, let hitElement else {
        return SampleResult(
            sampleLabel: spec.label,
            screenX: Int(point.x.rounded()),
            screenY: Int(point.y.rounded()),
            hitRolePath: [],
            hitActionPath: [],
            hitFramePath: [],
            topContainerRole: "",
            containsAXToolbar: false,
            containsAXTabGroup: false,
            containsInteractiveControl: false,
            containsStaticText: false,
            containsDuplicateLeafGroup: false,
            structureClass: "unsupported",
            riskLevel: "high",
            recommendedGUICheck: "",
            notes: "AXUIElementCopyElementAtPosition failed with \(hitError.rawValue)"
        )
    }

    let chain = rolesAndAncestors(from: hitElement, window: window)
    let topContainerRole = chain.first(where: {
        $0.role == kAXToolbarRole as String || $0.role == "AXTabGroup" || $0.role == kAXWindowRole as String
    })?.role ?? chain.last?.role ?? ""
    let hitRolePath = chain.map(\.role)
    let hitActionPath = chain.map { $0.actions.joined(separator: "&") }
    let hitFramePath = chain.map { $0.frame.map(NSStringFromRect) ?? "" }
    let containsToolbar = hitRolePath.contains(kAXToolbarRole as String)
    let containsTabGroup = hitRolePath.contains("AXTabGroup")
    let containsStaticText = hitRolePath.contains(kAXStaticTextRole as String)
    let containsInteractive = chain.contains { interactiveRole($0.role, actions: $0.actions) }
    let containsDuplicateLeafGroup = hitRolePath.count >= 2
        && hitRolePath[0] == kAXGroupRole as String
        && hitRolePath[1] == kAXGroupRole as String
        && framesNearlyEqual(chain[0].frame, chain[1].frame)
    let classification = classify(sampleLabel: spec.label, chain: chain)

    return SampleResult(
        sampleLabel: spec.label,
        screenX: Int(point.x.rounded()),
        screenY: Int(point.y.rounded()),
        hitRolePath: hitRolePath,
        hitActionPath: hitActionPath,
        hitFramePath: hitFramePath,
        topContainerRole: topContainerRole,
        containsAXToolbar: containsToolbar,
        containsAXTabGroup: containsTabGroup,
        containsInteractiveControl: containsInteractive,
        containsStaticText: containsStaticText,
        containsDuplicateLeafGroup: containsDuplicateLeafGroup,
        structureClass: classification.0,
        riskLevel: classification.1,
        recommendedGUICheck: classification.2,
        notes: classification.3
    )
}

encodeAndExit(
    ProbeResult(
        appName: appName,
        bundleID: bundleID,
        family: family,
        priority: priority,
        sampleProfile: sampleProfile,
        status: "ok",
        windowFrame: NSStringFromRect(windowFrame),
        samples: samples,
        notes: ""
    )
)
