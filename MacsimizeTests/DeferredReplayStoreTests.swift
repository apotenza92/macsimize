import ApplicationServices
import XCTest
@testable import Macsimize

final class DeferredReplayStoreTests: XCTestCase {
    func testTakeReturnsStoredSequenceAndClearsToken() {
        let store = DeferredReplayStore()
        let token = store.store([])

        XCTAssertEqual(store.take(token)?.count, 0)
        XCTAssertNil(store.take(token))
        XCTAssertTrue(store.isEmpty)
    }

    func testRemoveClearsStoredSequenceWithoutReplaying() {
        let store = DeferredReplayStore()
        let token = store.store([])

        store.remove(token)

        XCTAssertNil(store.take(token))
        XCTAssertTrue(store.isEmpty)
    }

    func testRemoveAllClearsEveryStoredSequence() {
        let store = DeferredReplayStore()
        _ = store.store([])
        _ = store.store([])

        store.removeAll()

        XCTAssertTrue(store.isEmpty)
    }

    func testReplaySequenceForFullScreenRemovesAlternateModifier() {
        let event = makeMouseEvent()
        event.flags = [.maskAlternate, .maskCommand]

        let replaySequence = EventTapService.replaySequence(for: .fullScreen, originalEvents: [event])

        XCTAssertEqual(replaySequence.count, 1)
        XCTAssertFalse(replaySequence[0].flags.contains(.maskAlternate))
        XCTAssertTrue(replaySequence[0].flags.contains(.maskCommand))
    }

    func testReplaySequenceForMaximizeKeepsOriginalModifiers() {
        let event = makeMouseEvent()
        event.flags = [.maskAlternate, .maskCommand]

        let replaySequence = EventTapService.replaySequence(for: .maximize, originalEvents: [event])

        XCTAssertEqual(replaySequence.count, 1)
        XCTAssertTrue(replaySequence[0].flags.contains(.maskAlternate))
        XCTAssertTrue(replaySequence[0].flags.contains(.maskCommand))
    }

    private func makeMouseEvent() -> CGEvent {
        let source = CGEventSource(stateID: .hidSystemState)!
        return CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        )!
    }
}
