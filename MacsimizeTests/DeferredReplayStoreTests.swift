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
}
