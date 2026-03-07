import Combine
import Foundation

final class SettingsStore: ObservableObject {
    private enum Key {
        static let selectedAction = "selectedAction"
        static let diagnosticsEnabled = "diagnosticsEnabled"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let showSettingsOnStartup = "showSettingsOnStartup"
        static let firstLaunchCompleted = "firstLaunchCompleted"
    }

    private let userDefaults: UserDefaults

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

    @Published var excludedBundleIDs: [String] {
        didSet {
            userDefaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs)
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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedSelectedAction = userDefaults.string(forKey: Key.selectedAction)
        let selectedAction = Self.migratedAction(from: storedSelectedAction)
        if storedSelectedAction != selectedAction.rawValue {
            userDefaults.set(selectedAction.rawValue, forKey: Key.selectedAction)
        }

        let diagnosticsEnabled = userDefaults.object(forKey: Key.diagnosticsEnabled) as? Bool ?? true
        let excludedBundleIDs = userDefaults.stringArray(forKey: Key.excludedBundleIDs) ?? []
        let showSettingsOnStartup = userDefaults.object(forKey: Key.showSettingsOnStartup) as? Bool ?? true
        let firstLaunchCompleted = userDefaults.object(forKey: Key.firstLaunchCompleted) as? Bool ?? false

        self.selectedAction = selectedAction
        self.diagnosticsEnabled = diagnosticsEnabled
        self.excludedBundleIDs = excludedBundleIDs
        self.showSettingsOnStartup = showSettingsOnStartup
        self.firstLaunchCompleted = firstLaunchCompleted
    }

    var excludedBundleIDsText: String {
        get {
            excludedBundleIDs.joined(separator: ", ")
        }
        set {
            excludedBundleIDs = Self.parseBundleIDs(from: newValue)
        }
    }

    func addExcludedBundleID(_ bundleIdentifier: String) {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        if !excludedBundleIDs.contains(normalized) {
            excludedBundleIDs.append(normalized)
            excludedBundleIDs.sort()
        }
    }

    func removeExcludedBundleID(_ bundleIdentifier: String) {
        excludedBundleIDs.removeAll { $0 == bundleIdentifier }
    }

    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }
        return excludedBundleIDs.contains(bundleIdentifier)
    }

    static func parseBundleIDs(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partialResult, item in
                if !partialResult.contains(item) {
                    partialResult.append(item)
                }
            }
            .sorted()
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
