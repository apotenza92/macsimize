import XCTest
@testable import Macsimize

final class SettingsStoreMigrationTests: XCTestCase {
    func testLegacyFirstLaunchCompletedMigratesToCompletedOnboarding() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "firstLaunchCompleted")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertTrue(store.isOnboardingCompleted)
        XCTAssertFalse(store.shouldPresentOnboarding)
        XCTAssertEqual(defaults.object(forKey: "onboardingCompleted") as? Bool, true)
    }

    func testExplicitStoredOnboardingStateWinsOverLegacyFirstLaunchFlag() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "firstLaunchCompleted")
        defaults.set(false, forKey: "onboardingCompleted")

        let store = SettingsStore(userDefaults: defaults)

        XCTAssertFalse(store.isOnboardingCompleted)
        XCTAssertTrue(store.shouldPresentOnboarding)
    }

    private func isolatedDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
        let suiteName = "MacsimizeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults", file: file, line: line)
            fatalError("Failed to create isolated defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
