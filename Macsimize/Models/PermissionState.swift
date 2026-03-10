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
            return AppStrings.permissionSummaryAccessibilityRequired
        }
        if !inputMonitoringGranted {
            return AppStrings.permissionSummaryInputMonitoringRequired
        }
        if eventTapRunning {
            return AppStrings.permissionSummaryReady
        }
        return AppStrings.permissionSummaryWaitingForEventTap
    }

    var detail: String {
        if !accessibilityTrusted {
            return AppStrings.permissionDetailAccessibilityRequired
        }
        if !inputMonitoringGranted {
            return AppStrings.permissionDetailInputMonitoringRequired
        }
        if secureEventInputEnabled {
            return AppStrings.permissionDetailSecureEventInput
        }
        if let lastFailureReason, !lastFailureReason.isEmpty {
            return lastFailureReason
        }
        if !eventTapRunning {
            return AppStrings.permissionDetailEventTapInactive
        }
        return AppStrings.permissionDetailInterceptingClicks(appName: AppIdentity.displayName)
    }

    var allRequiredPermissionsGranted: Bool {
        accessibilityTrusted && inputMonitoringGranted
    }

    var hasVisibleIssue: Bool {
        if !accessibilityTrusted || !inputMonitoringGranted {
            return true
        }
        if secureEventInputEnabled {
            return true
        }
        if let lastFailureReason, !lastFailureReason.isEmpty {
            return true
        }
        return !eventTapRunning
    }
}
