import ApplicationServices
import CoreGraphics
import XCTest
@testable import Macsimize

final class WindowActionEngineTests: XCTestCase {
    func testFullScreenReturnsPassThroughOnly() {
        XCTAssertEqual(WindowActionEngine.plan(for: .fullScreen), [.fullScreen])

        let strategy = MaximizePerformerStub(result: Self.successResult())
        let engine = WindowActionEngine(maximizeStrategy: strategy, diagnostics: DebugDiagnostics())

        let outcome = engine.perform(mode: .fullScreen, context: Self.makeContext())

        XCTAssertFalse(outcome.handled)
        XCTAssertEqual(outcome.chosenPath, .fullScreen)
        XCTAssertEqual(outcome.failureDisposition, .replayOriginalClick)
        XCTAssertEqual(strategy.performCallCount, 0)
    }

    func testMaximizeInvokesDeterministicStrategyOnly() {
        XCTAssertEqual(WindowActionEngine.plan(for: .maximize), [.maximize])

        let strategy = MaximizePerformerStub(result: Self.successResult())
        let engine = WindowActionEngine(maximizeStrategy: strategy, diagnostics: DebugDiagnostics())

        let outcome = engine.perform(mode: .maximize, context: Self.makeContext())

        XCTAssertTrue(outcome.handled)
        XCTAssertEqual(outcome.chosenPath, .maximize)
        XCTAssertEqual(outcome.failureDisposition, .dropInterceptedClick)
        XCTAssertEqual(strategy.performCallCount, 1)
    }

    func testMaximizeSkipsNonResizableWindows() {
        let strategy = MaximizePerformerStub(result: Self.successResult())
        let engine = WindowActionEngine(maximizeStrategy: strategy, diagnostics: DebugDiagnostics())

        let outcome = engine.perform(mode: .maximize, context: Self.makeContext(isResizable: false))

        XCTAssertFalse(outcome.handled)
        XCTAssertNil(outcome.chosenPath)
        XCTAssertEqual(outcome.failureDisposition, .dropInterceptedClick)
        XCTAssertEqual(strategy.performCallCount, 0)
        XCTAssertTrue(outcome.notes.contains { $0.contains("not appear to be resizable") })
    }

    func testMaximizePropagatesMissingFrameFailure() {
        let strategy = MaximizePerformerStub(result: MaximizeResult(
            succeeded: false,
            appliedRect: nil,
            restored: false,
            positionApplied: false,
            postApplyFrame: nil,
            notes: ["Window frame unavailable."]
        ))
        let engine = WindowActionEngine(maximizeStrategy: strategy, diagnostics: DebugDiagnostics())

        let outcome = engine.perform(mode: .maximize, context: Self.makeContext(windowFrame: nil))

        XCTAssertFalse(outcome.handled)
        XCTAssertEqual(outcome.chosenPath, .maximize)
        XCTAssertEqual(outcome.failureDisposition, .dropInterceptedClick)
        XCTAssertEqual(strategy.performCallCount, 1)
        XCTAssertEqual(outcome.notes, ["Window frame unavailable."])
    }

    private static func successResult() -> MaximizeResult {
        MaximizeResult(
            succeeded: true,
            appliedRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
            restored: false,
            positionApplied: true,
            postApplyFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            notes: ["maximize succeeded"]
        )
    }

    private static func makeContext(
        windowFrame: CGRect? = CGRect(x: 10, y: 10, width: 500, height: 400),
        isResizable: Bool = true
    ) -> ClickedWindowContext {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        return ClickedWindowContext(
            appName: "Fixture",
            bundleIdentifier: "com.example.fixture",
            pid: ProcessInfo.processInfo.processIdentifier,
            clickLocation: CGPoint(x: 100, y: 100),
            buttonElement: element,
            windowElement: element,
            windowIdentifier: "fixture-window",
            windowNumber: 1,
            windowTitle: "Fixture",
            elementRole: "AXButton",
            elementSubrole: "AXZoomButton",
            availableActions: ["AXPress"],
            windowFrame: windowFrame,
            canSetPosition: true,
            canSetSize: true,
            isResizable: isResizable,
            isMainWindow: true,
            isFocusedWindow: true
        )
    }
}

private final class MaximizePerformerStub: MaximizePerforming {
    let result: MaximizeResult
    private(set) var performCallCount = 0

    init(result: MaximizeResult) {
        self.result = result
    }

    func perform(on context: ClickedWindowContext) -> MaximizeResult {
        performCallCount += 1
        return result
    }
}
