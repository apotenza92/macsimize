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
    private var needsInitialContentFit = true
    private var measuredMaximumHeight = SettingsLayout.defaultSettingsHeight
    private var needsSettingsCentering = false

    init(appState: AppState) {
        self.appState = appState
        self.currentMode = appState.settings.shouldPresentOnboarding ? .onboarding : .settings

        let hostingController = NSHostingController(rootView: SettingsRootView(appState: appState))
        // Window sizing is owned here; SwiftUI must not replace its maximum size.
        hostingController.sizingOptions = []
        self.hostingController = hostingController
        let window = NSWindow(contentViewController: hostingController)

        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false

        super.init(window: window)

        configureWindow(for: currentMode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(request: InitialWindowRequest = .settings(explicit: false)) {
        guard let window else {
            return
        }

        applyWindowMode(for: request)
        if !needsInitialContentFit {
            apply(
                contentSize: NSSize(width: SettingsLayout.detailWidth, height: measuredMaximumHeight),
                to: window,
                on: activeScreen()
            )
        }

        RuntimeLogger.log("Showing \(currentMode == .onboarding ? "onboarding" : "settings") window")
        bringToFront(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
            guard let window else { return }
            self.bringToFront(window)
            RuntimeLogger.log("Settings window fronting pass completed")
        }
    }

    private func applyWindowMode(for request: InitialWindowRequest) {
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
            return
        }

        currentMode = requestedMode
        configureWindow(for: requestedMode)
    }

    private func configureWindow(for mode: WindowMode) {
        guard let window else {
            return
        }

        let contentMode: SettingsRootView.ContentMode = switch mode {
        case .onboarding:
            .onboarding
        case .settings:
            .settings
        }
        needsInitialContentFit = true
        needsSettingsCentering = mode == .settings
        hostingController.rootView = SettingsRootView(
            appState: appState,
            contentMode: contentMode,
            contentHeightDidChange: { [weak self] height in
                guard let self, self.currentMode == mode else { return }
                self.updateContentHeight(height)
            },
            onboardingCompleted: { [weak self] openSettings in
                guard let self else { return }
                if openSettings {
                    self.show(request: .settings(explicit: true))
                } else {
                    self.close()
                }
            }
        )
        window.title = mode.title

        window.styleMask.remove(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic

        window.styleMask.remove(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = NSSize(width: SettingsLayout.detailWidth, height: 180)
        window.contentMaxSize = NSSize(width: SettingsLayout.detailWidth, height: CGFloat.greatestFiniteMagnitude)

        refitWindow()
    }

    private func refitWindow() {
        guard let window else {
            return
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = NSSize(width: SettingsLayout.detailWidth, height: SettingsLayout.defaultSettingsHeight)
        let screen = activeScreen()
        let maximumContentSize = screen.map { window.contentRect(forFrameRect: $0.visibleFrame).size } ?? fittingSize
        let contentSize = Self.contentSize(
            fittingSize: fittingSize,
            maximumSize: maximumContentSize
        )
        apply(
            contentSize: contentSize,
            to: window,
            on: screen
        )
    }

    private func updateContentHeight(_ naturalHeight: CGFloat) {
        guard let window, naturalHeight > 0 else { return }
        let screen = activeScreen()
        let availableHeight = screen.map { window.contentRect(forFrameRect: $0.visibleFrame).height } ?? naturalHeight
        let maximumHeight = min(ceil(naturalHeight), availableHeight)
        measuredMaximumHeight = maximumHeight
        RuntimeLogger.log("Window content height: \(naturalHeight), maximum: \(maximumHeight)")
        let currentHeight = window.contentRect(forFrameRect: window.frame).height
        let targetHeight = maximumHeight
        needsInitialContentFit = false
        let fittedSize = NSSize(width: SettingsLayout.detailWidth, height: maximumHeight)
        window.contentMinSize = .zero
        window.contentMaxSize = fittedSize
        window.contentMinSize = fittedSize
        if needsSettingsCentering || abs(currentHeight - targetHeight) > 0.5 {
            apply(
                contentSize: NSSize(width: SettingsLayout.detailWidth, height: targetHeight),
                to: window,
                on: screen
            )
        }
        needsSettingsCentering = false
    }

    private func apply(
        contentSize: NSSize,
        to window: NSWindow,
        on screen: NSScreen?
    ) {
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))

        // Keep the first Settings presentation centred through its final content fit,
        // including when reusing the visible onboarding window on another display.
        if needsSettingsCentering, let screen {
            window.setFrame(
                Self.centeredFrame(size: newFrame.size, in: screen.visibleFrame),
                display: window.isVisible,
                animate: false
            )
            return
        }

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
            window.setFrame(targetFrame, display: true, animate: false)
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
        if needsSettingsCentering {
            return NSScreen.screens.first ?? NSScreen.main
        }
        if currentMode == .settings, let screen = window?.screen {
            return screen
        }
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
