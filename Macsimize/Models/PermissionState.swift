import Foundation

struct PermissionState: Equatable {
    var accessibilityTrusted: Bool
    var inputMonitoringGranted: Bool
    var secureEventInputEnabled: Bool
    var eventTapRunning: Bool
    var lastFailureReason: String?

    static let unknown = PermissionState(
        accessibilityTrusted: false,
        inputMonitoringGranted: false,
        secureEventInputEnabled: false,
        eventTapRunning: false,
        lastFailureReason: nil
    )

    var summary: String {
        if !accessibilityTrusted {
            return "Accessibility required"
        }
        if !inputMonitoringGranted {
            return "Input Monitoring required"
        }
        if eventTapRunning {
            return "Ready"
        }
        return "Waiting for event tap"
    }

    var detail: String {
        if !accessibilityTrusted {
            return "Grant Accessibility access in System Settings > Privacy & Security > Accessibility."
        }
        if !inputMonitoringGranted {
            return "Grant Input Monitoring access in System Settings > Privacy & Security > Input Monitoring, then return here."
        }
        if secureEventInputEnabled {
            return "Secure Event Input is active. Event interception may be limited until the blocking app stops using secure input."
        }
        if let lastFailureReason, !lastFailureReason.isEmpty {
            return lastFailureReason
        }
        return "Macsimize is ready to start intercepting clean green-button clicks."
    }

    var allRequiredPermissionsGranted: Bool {
        accessibilityTrusted && inputMonitoringGranted
    }
}
