import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let appDisplayName: String
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var appDelegate: AppDelegate?
    private let menu = NSMenu()
    private let maximizeAllItem = NSMenuItem(title: AppStrings.maximizeAllMenuTitle, action: #selector(maximizeAllWindows), keyEquivalent: "")
    private let restoreAllItem = NSMenuItem(title: AppStrings.restoreAllMenuTitle, action: #selector(restoreAllWindows), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: AppStrings.settingsMenuTitle, action: #selector(openSettings), keyEquivalent: ",")
    private let quitItem: NSMenuItem

    init(appDelegate: AppDelegate) {
        let appDisplayName = AppIdentity.displayName
        self.appDisplayName = appDisplayName
        self.appDelegate = appDelegate
        quitItem = NSMenuItem(title: AppStrings.quitMenuTitle(appName: appDisplayName), action: #selector(quitApp), keyEquivalent: "q")
        super.init()
        configureStatusItem()
        configureMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = MacsimizeGlyphImage.make(size: NSSize(width: 18, height: 18))
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(appDisplayName)
        button.toolTip = appDisplayName
    }

    private func configureMenu() {
        maximizeAllItem.target = self
        restoreAllItem.target = self
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]

        menu.removeAllItems()
        menu.addItem(maximizeAllItem)
        menu.addItem(restoreAllItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func openSettings() {
        appDelegate?.showSettingsWindow()
    }

    @objc
    private func maximizeAllWindows() {
        appDelegate?.maximizeAllCurrentSpaceWindows()
    }

    @objc
    private func restoreAllWindows() {
        appDelegate?.restoreAllCurrentSpaceWindows()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

@MainActor
private enum MacsimizeGlyphImage {
    private static let image = makeSymbolImage()

    static func make(size _: NSSize) -> NSImage {
        image
    }

    private static func makeSymbolImage() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
        guard let image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: AppStrings.appAccessibilityLabel)?
            .withSymbolConfiguration(configuration) else {
            let fallback = NSImage(size: NSSize(width: 18, height: 18))
            fallback.isTemplate = true
            return fallback
        }
        image.isTemplate = true
        return image
    }
}
