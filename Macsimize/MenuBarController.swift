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

private enum MacsimizeGlyphImage {
    static func make(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        drawCirclePlusGlyph(in: NSRect(origin: .zero, size: size), strokeColor: .labelColor, lineWidth: 1.85)

        image.isTemplate = true
        return image
    }

    private static func drawCirclePlusGlyph(in rect: NSRect, strokeColor: NSColor, lineWidth: CGFloat) {
        NSGraphicsContext.saveGraphicsState()

        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 24.0, yBy: rect.height / 24.0)
        transform.concat()

        strokeColor.setStroke()

        let circle = NSBezierPath(ovalIn: NSRect(x: 2.4, y: 2.4, width: 19.2, height: 19.2))
        circle.lineWidth = lineWidth
        circle.lineJoinStyle = .round
        circle.lineCapStyle = .round
        circle.stroke()

        let horizontal = NSBezierPath()
        horizontal.lineWidth = lineWidth
        horizontal.lineCapStyle = .round
        horizontal.move(to: NSPoint(x: 7.0, y: 12.0))
        horizontal.line(to: NSPoint(x: 17.0, y: 12.0))
        horizontal.stroke()

        let vertical = NSBezierPath()
        vertical.lineWidth = lineWidth
        vertical.lineCapStyle = .round
        vertical.move(to: NSPoint(x: 12.0, y: 7.0))
        vertical.line(to: NSPoint(x: 12.0, y: 17.0))
        vertical.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }
}
