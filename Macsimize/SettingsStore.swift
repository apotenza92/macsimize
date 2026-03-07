import Combine
import Foundation
import ServiceManagement

final class SettingsStore: ObservableObject {
    private enum Key {
        static let selectedAction = "selectedAction"
        static let diagnosticsEnabled = "diagnosticsEnabled"
        static let showSettingsOnStartup = "showSettingsOnStartup"
        static let firstLaunchCompleted = "firstLaunchCompleted"
        static let startAtLogin = "startAtLogin"
        static let updateCheckFrequency = "updateCheckFrequency"
        static let lastUpdateCheckTimestamp = "lastUpdateCheckTimestamp"
    }

    private let userDefaults: UserDefaults
    private var applyingLoginItemChange = false

    @Published var selectedAction: WindowActionMode {
        didSet {
            userDefaults.set(selectedAction.rawValue, forKey: Key.selectedAction)
        }
    }

    @Published var diagnosticsEnabled: Bool {
        didSet {
            userDefaults.set(diagnosticsEnabled, forKey: Key.diagnosticsEnabled)
        }
    }

    @Published var showSettingsOnStartup: Bool {
        didSet {
            userDefaults.set(showSettingsOnStartup, forKey: Key.showSettingsOnStartup)
        }
    }

    @Published var firstLaunchCompleted: Bool {
        didSet {
            userDefaults.set(firstLaunchCompleted, forKey: Key.firstLaunchCompleted)
        }
    }

    @Published var startAtLogin: Bool {
        didSet {
            guard !applyingLoginItemChange else {
                return
            }

            applyingLoginItemChange = true
            do {
                if startAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                userDefaults.set(startAtLogin, forKey: Key.startAtLogin)
            } catch {
                RuntimeLogger.log("Failed to update login item state: \(error.localizedDescription)")
                let enabled = SMAppService.mainApp.status == .enabled
                startAtLogin = enabled
                userDefaults.set(enabled, forKey: Key.startAtLogin)
            }
            applyingLoginItemChange = false
        }
    }

    @Published var updateCheckFrequency: UpdateCheckFrequency {
        didSet {
            userDefaults.set(updateCheckFrequency.rawValue, forKey: Key.updateCheckFrequency)
        }
    }

    @Published private(set) var lastUpdateCheckTimestamp: TimeInterval {
        didSet {
            userDefaults.set(lastUpdateCheckTimestamp, forKey: Key.lastUpdateCheckTimestamp)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedSelectedAction = userDefaults.string(forKey: Key.selectedAction)
        let selectedAction = Self.migratedAction(from: storedSelectedAction)
        if storedSelectedAction != selectedAction.rawValue {
            userDefaults.set(selectedAction.rawValue, forKey: Key.selectedAction)
        }

        let diagnosticsEnabled = userDefaults.object(forKey: Key.diagnosticsEnabled) as? Bool ?? true
        let showSettingsOnStartup = userDefaults.object(forKey: Key.showSettingsOnStartup) as? Bool ?? false
        let firstLaunchCompleted = userDefaults.object(forKey: Key.firstLaunchCompleted) as? Bool ?? false
        let loginItemEnabled = SMAppService.mainApp.status == .enabled
        let updateCheckFrequency = UpdateCheckFrequency(
            rawValue: userDefaults.string(forKey: Key.updateCheckFrequency) ?? ""
        ) ?? .daily
        let lastUpdateCheckTimestamp = userDefaults.object(forKey: Key.lastUpdateCheckTimestamp) as? TimeInterval ?? 0
        let startAtLogin: Bool
        if loginItemEnabled {
            startAtLogin = true
        } else {
            startAtLogin = userDefaults.object(forKey: Key.startAtLogin) as? Bool ?? false
        }

        self.selectedAction = selectedAction
        self.diagnosticsEnabled = diagnosticsEnabled
        self.showSettingsOnStartup = showSettingsOnStartup
        self.firstLaunchCompleted = firstLaunchCompleted
        self.startAtLogin = startAtLogin
        self.updateCheckFrequency = updateCheckFrequency
        self.lastUpdateCheckTimestamp = lastUpdateCheckTimestamp
        userDefaults.removeObject(forKey: "excludedBundleIDs")
    }

    func markUpdateCheckNow(now: Date = Date()) {
        lastUpdateCheckTimestamp = now.timeIntervalSince1970
    }

    func shouldCheckForUpdatesOnLaunch(now: Date = Date()) -> Bool {
        switch updateCheckFrequency {
        case .never:
            return false
        case .startup:
            return true
        case .hourly, .sixHours, .twelveHours, .daily, .weekly:
            guard let interval = updateCheckFrequency.interval else { return false }
            let elapsed = now.timeIntervalSince1970 - lastUpdateCheckTimestamp
            return elapsed >= interval
        }
    }

    private static func migratedAction(from storedRawValue: String?) -> WindowActionMode {
        guard let storedRawValue else {
            return .maximize
        }

        if let currentMode = WindowActionMode(rawValue: storedRawValue) {
            return currentMode
        }

        switch storedRawValue {
        case "systemDefault":
            return .fullScreen
        case "fillPublic", "fillPrivate", "zoomExperimental":
            return .maximize
        default:
            return .maximize
        }
    }
}
