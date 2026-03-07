import SwiftUI

@main
struct MacsimizeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        UserDefaults.standard.set(250, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
