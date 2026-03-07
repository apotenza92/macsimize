import ApplicationServices
import CoreGraphics
import Foundation

struct ClickedWindowContext {
    let appName: String
    let bundleIdentifier: String?
    let pid: pid_t
    let clickLocation: CGPoint
    let buttonElement: AXUIElement
    let windowElement: AXUIElement
    let windowIdentifier: String
    let windowNumber: Int?
    let windowTitle: String?
    let elementRole: String?
    let elementSubrole: String?
    let availableActions: [String]
    let windowFrame: CGRect?
    let canSetPosition: Bool
    let canSetSize: Bool
    let isResizable: Bool
    let isMainWindow: Bool
    let isFocusedWindow: Bool

    var appDescriptor: String {
        if let bundleIdentifier {
            return "\(appName) (\(bundleIdentifier))"
        }
        return appName
    }
}
