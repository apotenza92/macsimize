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

        let stroke = NSColor.labelColor
        stroke.setStroke()

        let inset = max(1.5, floor(size.width * 0.16))
        let corner = max(3.0, floor(size.width * 0.26))
        let lineWidth = max(1.6, size.width * 0.11)

        func path(points: [NSPoint]) {
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()
        }

        let minX = inset
        let maxX = size.width - inset
        let minY = inset
        let maxY = size.height - inset

        path(points: [
            NSPoint(x: minX + corner, y: maxY),
            NSPoint(x: minX, y: maxY),
            NSPoint(x: minX, y: maxY - corner)
        ])
        path(points: [
            NSPoint(x: maxX - corner, y: maxY),
            NSPoint(x: maxX, y: maxY),
            NSPoint(x: maxX, y: maxY - corner)
        ])
        path(points: [
            NSPoint(x: minX, y: minY + corner),
            NSPoint(x: minX, y: minY),
            NSPoint(x: minX + corner, y: minY)
        ])
        path(points: [
            NSPoint(x: maxX - corner, y: minY),
            NSPoint(x: maxX, y: minY),
            NSPoint(x: maxX, y: minY + corner)
        ])

        let centerBar = NSBezierPath()
        centerBar.lineWidth = max(1.2, lineWidth * 0.86)
        centerBar.lineCapStyle = .round
        centerBar.move(to: NSPoint(x: minX + corner * 0.9, y: size.height / 2))
        centerBar.line(to: NSPoint(x: maxX - corner * 0.9, y: size.height / 2))
        centerBar.stroke()

        image.isTemplate = true
        return image
    }
}
