import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private enum WindowMode: Equatable {
        case onboarding
        case settings

        var title: String {
            switch self {
            case .onboarding:
                return "\(AppIdentity.displayName) Setup"
            case .settings:
                return AppIdentity.settingsWindowTitle
            }
        }

        var fixedContentSize: NSSize? {
            switch self {
            case .onboarding:
                return NSSize(width: 420, height: 640)
            case .settings:
                return nil
            }
        }

        var minimumContentSize: NSSize {
            switch self {
            case .onboarding:
                return fixedContentSize ?? NSSize(width: 420, height: 640)
            case .settings:
                return NSSize(width: 360, height: 560)
            }
        }

        var allowsResizing: Bool {
            switch self {
            case .onboarding:
                return false
            case .settings:
                return true
            }
        }

        var frameAutosaveName: String {
            switch self {
            case .onboarding:
                return "Macsimize.OnboardingWindowFrame"
            case .settings:
                return "Macsimize.SettingsWindowFrame"
            }
        }
    }

    private let appState: AppState
    private let hostingController: SettingsHostingController<SettingsRootView>
    private var currentMode: WindowMode

    init(appState: AppState) {
        self.appState = appState
        self.currentMode = appState.settings.shouldPresentOnboarding ? .onboarding : .settings

        let hostingController = SettingsHostingController(rootView: SettingsRootView(appState: appState))
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference

        super.init(window: window)

        configureWindow(for: currentMode, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(request: InitialWindowRequest = .settings(explicit: false)) {
        guard let window else {
            return
        }

        applyWindowMode(for: request, animated: window.isVisible)

        RuntimeLogger.log("Showing \(currentMode == .onboarding ? "onboarding" : "settings") window")
        bringToFront(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
            guard let window else { return }
            self.bringToFront(window)
            RuntimeLogger.log("Settings window fronting pass completed")
        }
    }

    private func applyWindowMode(for request: InitialWindowRequest, animated: Bool) {
        let requestedMode: WindowMode
        switch request {
        case .onboarding:
            requestedMode = .onboarding
        case .none:
            requestedMode = appState.settings.shouldPresentOnboarding ? .onboarding : .settings
        case let .settings(explicit):
            if explicit {
                requestedMode = .settings
            } else {
                requestedMode = appState.settings.shouldPresentOnboarding ? .onboarding : .settings
            }
        }

        guard requestedMode != currentMode || window?.frameAutosaveName != requestedMode.frameAutosaveName else {
            configureWindow(for: requestedMode, animated: animated)
            return
        }

        window?.saveFrame(usingName: currentMode.frameAutosaveName)
        currentMode = requestedMode
        configureWindow(for: requestedMode, animated: animated)
    }

    private func configureWindow(for mode: WindowMode, animated: Bool) {
        guard let window else {
            return
        }

        let contentMode: SettingsRootView.ContentMode = switch mode {
        case .onboarding:
            .onboarding
        case .settings:
            .settings
        }
        hostingController.rootView = SettingsRootView(appState: appState, contentMode: contentMode)
        window.title = mode.title

        var styleMask = window.styleMask
        if mode.allowsResizing {
            styleMask.insert(.resizable)
        } else {
            styleMask.remove(.resizable)
        }
        window.styleMask = styleMask

        window.contentMinSize = mode.minimumContentSize
        window.contentMaxSize = mode.fixedContentSize ?? NSSize(width: 10_000, height: 10_000)
        window.setFrameAutosaveName(mode.frameAutosaveName)

        let restoredFrame = window.setFrameUsingName(mode.frameAutosaveName)
        if let fixedContentSize = mode.fixedContentSize {
            apply(contentSize: fixedContentSize, to: window, animated: animated, centerIfNeeded: !restoredFrame)
            return
        }

        if restoredFrame {
            return
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let contentSize = NSSize(
            width: max(fittingSize.width, mode.minimumContentSize.width),
            height: max(fittingSize.height, mode.minimumContentSize.height)
        )
        apply(contentSize: contentSize, to: window, animated: animated, centerIfNeeded: true)
    }

    private func apply(contentSize: NSSize, to window: NSWindow, animated: Bool, centerIfNeeded: Bool) {
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))

        if window.isVisible {
            let currentFrame = window.frame
            let origin = NSPoint(
                x: currentFrame.midX - (newFrame.width / 2),
                y: currentFrame.midY - (newFrame.height / 2)
            )
            window.setFrame(NSRect(origin: origin, size: newFrame.size), display: true, animate: animated)
        } else {
            let currentFrame = window.frame
            window.setFrame(NSRect(origin: currentFrame.origin, size: newFrame.size), display: false)
            if centerIfNeeded {
                window.center()
            }
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

@MainActor
private final class SettingsHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = ZeroSafeAreaHostingView(rootView: rootView)
    }
}

@MainActor
private final class ZeroSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    private let zeroInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    override var safeAreaInsets: NSEdgeInsets {
        zeroInsets
    }

    override var safeAreaRect: NSRect {
        bounds
    }

    override var additionalSafeAreaInsets: NSEdgeInsets {
        get { zeroInsets }
        set {}
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layoutSubtreeIfNeeded()
    }
}
