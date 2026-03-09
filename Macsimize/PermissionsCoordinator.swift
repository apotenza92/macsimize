import ApplicationServices
import Combine
import Foundation

final class PermissionsCoordinator: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: PermissionState = .unknown

    private var permissionPollTask: Task<Void, Never>?

    func refresh(promptIfNeeded: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": promptIfNeeded] as CFDictionary
        let accessibilityTrusted = AXIsProcessTrustedWithOptions(options)

        if promptIfNeeded && !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        let nextState = PermissionState(
            accessibilityTrusted: accessibilityTrusted,
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            secureEventInputEnabled: SecureEventInput.isEnabled(),
            eventTapRunning: state.eventTapRunning,
            lastFailureReason: state.lastFailureReason
        )

        publish(nextState)
    }

    func requestInputMonitoringPermission() {
        _ = CGRequestListenEventAccess()
        refresh(promptIfNeeded: false)
    }

    func updateEventTapStatus(isRunning: Bool, lastFailureReason: String?) {
        let currentState = state
        let nextState = PermissionState(
            accessibilityTrusted: currentState.accessibilityTrusted,
            inputMonitoringGranted: currentState.inputMonitoringGranted,
            secureEventInputEnabled: currentState.secureEventInputEnabled,
            eventTapRunning: isRunning,
            lastFailureReason: lastFailureReason
        )

        publish(nextState)
    }

    func startMonitoringForChanges(pollInterval: TimeInterval = 1.0) {
        permissionPollTask?.cancel()
        permissionPollTask = Task { [weak self] in
            guard let self else {
                return
            }

            let intervalNs = UInt64(max(pollInterval, 0.2) * 1_000_000_000)
            while !Task.isCancelled {
                let nextState = PermissionState(
                    accessibilityTrusted: AXIsProcessTrusted(),
                    inputMonitoringGranted: CGPreflightListenEventAccess(),
                    secureEventInputEnabled: SecureEventInput.isEnabled(),
                    eventTapRunning: self.state.eventTapRunning,
                    lastFailureReason: self.state.lastFailureReason
                )

                self.publish(nextState)

                if nextState.allRequiredPermissionsGranted {
                    self.permissionPollTask = nil
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: intervalNs)
                } catch {
                    return
                }
            }
        }
    }

    func stopMonitoringForChanges() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
    }

    private func publish(_ nextState: PermissionState) {
        if Thread.isMainThread {
            guard state != nextState else {
                return
            }
            state = nextState
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state != nextState else {
                    return
                }
                self.state = nextState
            }
        }
    }

    deinit {
        permissionPollTask?.cancel()
    }
}
