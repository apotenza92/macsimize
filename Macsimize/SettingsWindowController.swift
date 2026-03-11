import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let minimumContentSize = NSSize(width: 360, height: 560)

    init(appState: AppState) {
        let view = PreferencesView(appState: appState)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)

        window.title = AppIdentity.settingsWindowTitle
        window.isReleasedWhenClosed = false
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let contentSize = NSSize(
            width: max(fittingSize.width, minimumContentSize.width),
            height: max(fittingSize.height, minimumContentSize.height)
        )
        window.contentMinSize = contentSize
        window.setContentSize(contentSize)

        super.init(window: window)
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
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
    }
}
