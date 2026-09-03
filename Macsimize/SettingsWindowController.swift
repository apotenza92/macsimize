import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    enum WindowMode: Equatable {
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

    }

    private let appState: AppState
    private let hostingController: NSHostingController<SettingsRootView>
    private var currentMode: WindowMode

    init(appState: AppState) {
        self.appState = appState
        self.currentMode = appState.settings.shouldPresentOnboarding ? .onboarding : .settings

        let hostingController = NSHostingController(rootView: SettingsRootView(appState: appState))
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false

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

        guard requestedMode != currentMode else {
            refitWindow(animated: animated)
            return
        }

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
        hostingController.rootView = SettingsRootView(
            appState: appState,
            contentMode: contentMode,
            contentDidChange: { [weak self] in
                self?.refitWindow(animated: self?.window?.isVisible == true)
            }
        )
        window.title = mode.title

        switch mode {
        case .onboarding:
            window.styleMask.remove(.fullSizeContentView)
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic
        case .settings:
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
        }

        refitWindow(animated: animated)
    }

    private func refitWindow(animated: Bool) {
        guard let window else {
            return
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let screen = activeScreen()
        let maximumContentSize = screen.map { window.contentRect(forFrameRect: $0.visibleFrame).size } ?? fittingSize
        let contentSize = Self.contentSize(
            fittingSize: fittingSize,
            maximumSize: maximumContentSize
        )
        apply(
            contentSize: contentSize,
            to: window,
            on: screen,
            animated: animated
        )
    }

    private func apply(
        contentSize: NSSize,
        to window: NSWindow,
        on screen: NSScreen?,
        animated: Bool
    ) {
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))

        if window.isVisible {
            let currentFrame = window.frame
            let targetFrame = switch currentMode {
            case .onboarding:
                NSRect(
                    x: currentFrame.midX - (newFrame.width / 2),
                    y: currentFrame.midY - (newFrame.height / 2),
                    width: newFrame.width,
                    height: newFrame.height
                )
            case .settings:
                Self.topLeftAnchoredFrame(size: newFrame.size, relativeTo: currentFrame)
            }
            window.setFrame(targetFrame, display: true, animate: animated)
        } else {
            if let screen {
                window.setFrame(
                    Self.centeredFrame(size: newFrame.size, in: screen.visibleFrame),
                    display: false
                )
                return
            }
        }
    }

    static func contentSize(fittingSize: NSSize, maximumSize: NSSize) -> NSSize {
        NSSize(
            width: min(fittingSize.width, maximumSize.width),
            height: min(fittingSize.height, maximumSize.height)
        )
    }

    static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    static func topLeftAnchoredFrame(size: NSSize, relativeTo currentFrame: NSRect) -> NSRect {
        NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
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
