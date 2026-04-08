import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let appDisplayName: String
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var appDelegate: AppDelegate?
    private let menu = NSMenu()
    private let maximizeAllItem = NSMenuItem(title: AppStrings.maximizeAllMenuTitle, action: #selector(maximizeAllWindows), keyEquivalent: "")
    private let restoreAllItem = NSMenuItem(title: AppStrings.restoreAllMenuTitle, action: #selector(restoreAllWindows), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: AppStrings.settingsMenuTitle, action: #selector(openSettings), keyEquivalent: ",")
    private let quitItem: NSMenuItem
    private var isInvalidated = false

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

        button.image = MacsimizeGlyphImage.menuBarImage(statusBarThickness: NSStatusBar.system.thickness)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
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

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
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
enum MacsimizeGlyphImage {
    private static let menuBarSymbolName = "plus.circle.fill"

    static func menuBarImage(statusBarThickness: CGFloat) -> NSImage {
        let targetSide = menuBarImageSideLength(statusBarThickness: statusBarThickness)
        let requestedSize = NSSize(width: targetSide, height: targetSide)
        let pointSize = max(11, targetSide - 2)
        return makeSymbolImage(pointSize: pointSize, preferredSize: requestedSize)
    }

    static func image(pointSize: CGFloat) -> NSImage {
        makeSymbolImage(pointSize: pointSize, preferredSize: nil)
    }

    static func menuBarImageSideLength(statusBarThickness: CGFloat) -> CGFloat {
        min(16, max(12, floor(statusBarThickness - 6)))
    }

    private static func makeSymbolImage(pointSize: CGFloat, preferredSize: NSSize?) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
        guard let image = NSImage(systemSymbolName: menuBarSymbolName, accessibilityDescription: AppStrings.appAccessibilityLabel)?
            .withSymbolConfiguration(configuration) else {
            let fallbackSize = preferredSize ?? NSSize(width: pointSize, height: pointSize)
            let fallback = NSImage(size: fallbackSize)
            fallback.isTemplate = true
            return fallback
        }
        if let preferredSize {
            image.size = preferredSize
        }
        image.isTemplate = true
        return image
    }
}
