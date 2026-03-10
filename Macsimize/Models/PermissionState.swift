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
            return "Grant Accessibility access in System Settings > Privacy & Security > Accessibility. Until then, Macsimize cannot intercept the green button, so macOS will keep using its normal behavior."
        }
        if !inputMonitoringGranted {
            return "Grant Input Monitoring access in System Settings > Privacy & Security > Input Monitoring. Until then, Macsimize cannot intercept the green button, so macOS will keep using its normal behavior."
        }
        if secureEventInputEnabled {
            return "Secure Event Input is active. Event interception may be limited until the blocking app stops using secure input, so native green-button behavior may still slip through."
        }
        if let lastFailureReason, !lastFailureReason.isEmpty {
            return lastFailureReason
        }
        if !eventTapRunning {
            return "Permissions are granted, but the event tap is not running yet. Macsimize is not active until the status changes to Ready."
        }
        return "\(AppIdentity.displayName) is ready to start intercepting clean green-button clicks."
    }

    var allRequiredPermissionsGranted: Bool {
        accessibilityTrusted && inputMonitoringGranted
    }
}
