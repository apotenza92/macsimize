import Foundation

enum WindowActionStep: String, Equatable {
    case fullScreen
    case maximize
}

enum WindowActionFailureDisposition: Equatable {
    case replayOriginalClick
    case dropInterceptedClick
}

struct WindowActionOutcome: Equatable {
    let handled: Bool
    let chosenPath: WindowActionStep?
    let notes: [String]
    let failureDisposition: WindowActionFailureDisposition
}

final class WindowActionEngine {
    static let syntheticEventMarker: Int64 = 0x4D414353

    private let maximizeStrategy: any MaximizePerforming
    private let diagnostics: DebugDiagnostics

    init(
        maximizeStrategy: any MaximizePerforming,
        diagnostics: DebugDiagnostics
    ) {
        self.maximizeStrategy = maximizeStrategy
        self.diagnostics = diagnostics
    }

    func perform(mode: WindowActionMode, context: ClickedWindowContext) -> WindowActionOutcome {
        switch mode {
        case .fullScreen:
            return WindowActionOutcome(
                handled: false,
                chosenPath: .fullScreen,
                notes: [AppStrings.actionEngineFullScreenPassThrough],
                failureDisposition: .replayOriginalClick
            )
        case .maximize:
            guard context.isResizable else {
                let notes = [AppStrings.actionEngineWindowNotResizable]
                diagnostics.logClickContext(context, chosenPath: "safety-skip", notes: notes)
                return WindowActionOutcome(
                    handled: false,
                    chosenPath: nil,
                    notes: notes,
                    failureDisposition: .dropInterceptedClick
                )
            }

            let result = maximizeStrategy.perform(on: context)
            if result.succeeded {
                diagnostics.logClickContext(context, chosenPath: WindowActionStep.maximize.rawValue, notes: result.notes)
                return WindowActionOutcome(
                    handled: true,
                    chosenPath: .maximize,
                    notes: result.notes,
                    failureDisposition: .dropInterceptedClick
                )
            }

            diagnostics.logClickContext(context, chosenPath: "failed", notes: result.notes)
            return WindowActionOutcome(
                handled: false,
                chosenPath: .maximize,
                notes: result.notes,
                failureDisposition: .dropInterceptedClick
            )
        }
    }

    static func plan(for mode: WindowActionMode) -> [WindowActionStep] {
        switch mode {
        case .fullScreen:
            return [.fullScreen]
        case .maximize:
            return [.maximize]
        }
    }
}
