import XCTest
@testable import Macsimize

final class SettingsStoreTests: XCTestCase {
    func testDefaultSelectedActionIsMaximize() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.selectedAction, .maximize)
        XCTAssertFalse(store.showSettingsOnStartup)
        XCTAssertFalse(store.firstLaunchCompleted)
        XCTAssertEqual(store.updateCheckFrequency, .daily)
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)
        store.selectedAction = .maximize
        store.diagnosticsEnabled = false
        store.showSettingsOnStartup = true
        store.firstLaunchCompleted = true
        store.updateCheckFrequency = .weekly

        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.selectedAction, .maximize)
        XCTAssertFalse(reloaded.diagnosticsEnabled)
        XCTAssertTrue(reloaded.showSettingsOnStartup)
        XCTAssertTrue(reloaded.firstLaunchCompleted)
        XCTAssertEqual(reloaded.updateCheckFrequency, .weekly)
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

    func testLegacySystemDefaultMigratesToMaximize() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set("systemDefault", forKey: "selectedAction")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.selectedAction, .maximize)
        XCTAssertEqual(defaults.string(forKey: "selectedAction"), WindowActionMode.maximize.rawValue)
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

    func testInitRemovesLegacyExcludedBundleIDs() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(["com.example.Legacy"], forKey: "excludedBundleIDs")

        _ = SettingsStore(userDefaults: defaults)

        XCTAssertNil(defaults.object(forKey: "excludedBundleIDs"))
    }

    func testUpdateCheckFrequencyStartupAlwaysChecks() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)
        store.updateCheckFrequency = .startup

        XCTAssertTrue(store.shouldCheckForUpdatesOnLaunch(now: Date(timeIntervalSince1970: 1)))
    }

    func testUpdateCheckFrequencyRespectsElapsedInterval() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = SettingsStore(userDefaults: defaults)
        store.updateCheckFrequency = .daily
        store.markUpdateCheckNow(now: Date(timeIntervalSince1970: 10))

        XCTAssertFalse(store.shouldCheckForUpdatesOnLaunch(now: Date(timeIntervalSince1970: 10 + (23 * 60 * 60))))
        XCTAssertTrue(store.shouldCheckForUpdatesOnLaunch(now: Date(timeIntervalSince1970: 10 + (24 * 60 * 60))))
    }

    func testSparkleLauncherServicePathIncludesBundleIdentifier() {
        let bundleURL = URL(fileURLWithPath: "/tmp/Macsimize.app", isDirectory: true)
        let path = UpdateManager.sparkleInstallerLauncherServicePath(
            bundleIdentifier: "pzc.Macsimize.beta",
            bundleURL: bundleURL
        )

        XCTAssertEqual(path, "/tmp/Macsimize.app/Contents/XPCServices/pzc.Macsimize.beta-spks.xpc")
    }

    func testHasSparkleInstallerLauncherServiceDetectsPresence() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let appURL = tempRoot.appendingPathComponent("Macsimize.app", isDirectory: true)
        let serviceURL = appURL
            .appendingPathComponent("Contents/XPCServices/pzc.Macsimize.beta-spks.xpc", isDirectory: true)
        try FileManager.default.createDirectory(at: serviceURL, withIntermediateDirectories: true)

        XCTAssertTrue(
            UpdateManager.hasSparkleInstallerLauncherService(
                bundleIdentifier: "pzc.Macsimize.beta",
                bundleURL: appURL
            )
        )
        XCTAssertFalse(
            UpdateManager.hasSparkleInstallerLauncherService(
                bundleIdentifier: "pzc.Macsimize",
                bundleURL: appURL
            )
        )
    }
}
