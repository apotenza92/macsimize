import XCTest
@testable import Macsimize

final class SettingsStoreTests: XCTestCase {
    func testDefaultSelectedActionIsMaximize() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.selectedAction, .maximize)
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)
        store.selectedAction = .maximize
        store.diagnosticsEnabled = false
        store.excludedBundleIDs = ["com.apple.Finder"]
        store.showSettingsOnStartup = true
        store.firstLaunchCompleted = true

        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.selectedAction, .maximize)
        XCTAssertFalse(reloaded.diagnosticsEnabled)
        XCTAssertEqual(reloaded.excludedBundleIDs, ["com.apple.Finder"])
        XCTAssertTrue(reloaded.showSettingsOnStartup)
        XCTAssertTrue(reloaded.firstLaunchCompleted)
    }

    func testFullScreenPersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)
        store.selectedAction = .fullScreen

        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.selectedAction, .fullScreen)
    }

    func testLegacySystemDefaultMigratesToFullScreen() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set("systemDefault", forKey: "selectedAction")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.selectedAction, .fullScreen)
        XCTAssertEqual(defaults.string(forKey: "selectedAction"), WindowActionMode.fullScreen.rawValue)
    }

    func testLegacyFillAndZoomValuesMigrateToMaximize() {
        for legacyRawValue in ["fillPublic", "fillPrivate", "zoomExperimental"] {
            let suiteName = "\(#function)-\(legacyRawValue)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            defaults.set(legacyRawValue, forKey: "selectedAction")

            let store = SettingsStore(userDefaults: defaults)

            XCTAssertEqual(store.selectedAction, .maximize, "Expected \(legacyRawValue) to migrate to maximize")
            XCTAssertEqual(defaults.string(forKey: "selectedAction"), WindowActionMode.maximize.rawValue)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    func testParseBundleIDsDeduplicatesAndTrimsValues() {
        let parsed = SettingsStore.parseBundleIDs(from: " com.apple.finder,com.apple.finder\n com.apple.TextEdit ")
        XCTAssertEqual(parsed, ["com.apple.TextEdit", "com.apple.finder"])
    }
}
