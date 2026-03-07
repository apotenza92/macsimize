import XCTest
@testable import Macsimize

final class WindowFrameStoreTests: XCTestCase {
    func testStoreAndPopFrame() {
        let store = WindowFrameStore()
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)

        store.store(frame: frame, for: "window-1")
        XCTAssertEqual(store.storedFrame(for: "window-1"), frame)
        XCTAssertEqual(store.popStoredFrame(for: "window-1"), frame)
        XCTAssertNil(store.storedFrame(for: "window-1"))
    }
}
