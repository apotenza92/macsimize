import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let defaults = UserDefaults.standard
    private let frameDefaultsKey = "settingsWindowFrame"
    private var frameObservers: [NSObjectProtocol] = []

    init(appState: AppState) {
        let view = PreferencesView(appState: appState)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = AppIdentity.settingsWindowTitle
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]

        hostingController.view.layoutSubtreeIfNeeded()
        window.setContentSize(hostingController.view.fittingSize)

        super.init(window: window)

        if !restoreFrame(for: window) {
            center(window: window)
        }
        observeFrameChanges(for: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }

        RuntimeLogger.log("Showing settings window")
        bringToFront(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
            guard let window else { return }
            self.bringToFront(window)
            RuntimeLogger.log("Settings window fronting pass completed")
        }
    }

    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
    }

    private func observeFrameChanges(for window: NSWindow) {
        let center = NotificationCenter.default
        frameObservers.append(
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.saveFrame(from: window)
                }
            }
        )
        frameObservers.append(
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.saveFrame(from: window)
                }
            }
        )
        frameObservers.append(
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.saveFrame(from: window)
                }
            }
        )
    }

    private func saveFrame(from window: NSWindow) {
        defaults.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
    }

    private func restoreFrame(for window: NSWindow) -> Bool {
        guard let frameString = defaults.string(forKey: frameDefaultsKey) else {
            return false
        }

        let frame = NSRectFromString(frameString)
        guard frame.width > 0, frame.height > 0 else {
            return false
        }

        let restoredFrame = NSRect(origin: frame.origin, size: window.frame.size)
        guard frameIsVisible(restoredFrame) else {
            return false
        }

        window.setFrame(restoredFrame, display: false)
        return true
    }

    private func frameIsVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private func center(window: NSWindow) {
        guard let targetScreen = targetScreen() else {
            window.center()
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (window.frame.width / 2),
            y: visibleFrame.midY - (window.frame.height / 2)
        )
        window.setFrameOrigin(origin)
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let hoveredScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return hoveredScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
