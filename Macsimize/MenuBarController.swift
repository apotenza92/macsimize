import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var appDelegate: AppDelegate?
    private let menu = NSMenu()
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Quit Macsimize", action: #selector(quitApp), keyEquivalent: "q")

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
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
        button.setAccessibilityLabel("Macsimize")
        button.toolTip = "Macsimize"
    }

    private func configureMenu() {
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]

        menu.removeAllItems()
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
        guard let image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Macsimize")?
            .withSymbolConfiguration(configuration) else {
            let fallback = NSImage(size: NSSize(width: 18, height: 18))
            fallback.isTemplate = true
            return fallback
        }
        image.isTemplate = true
        return image
    }
}
