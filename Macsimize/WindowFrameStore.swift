import CoreGraphics
import Foundation

struct StoredWindowFrameState: Equatable {
    let originalFrame: CGRect
    let lastAppliedMaximizeFrame: CGRect?
}

final class WindowFrameStore {
    private let lock = NSLock()
    private var frames: [String: StoredWindowFrameState] = [:]

    func store(frame: CGRect, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        frames[identifier] = StoredWindowFrameState(originalFrame: frame, lastAppliedMaximizeFrame: nil)
    }

    func storeTransition(originalFrame: CGRect, maximizedFrame: CGRect, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        frames[identifier] = StoredWindowFrameState(originalFrame: originalFrame, lastAppliedMaximizeFrame: maximizedFrame)
    }

    func storedFrame(for identifier: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return frames[identifier]?.originalFrame
    }

    func storedState(for identifier: String) -> StoredWindowFrameState? {
        lock.lock()
        defer { lock.unlock() }
        return frames[identifier]
    }

    @discardableResult
    func popStoredFrame(for identifier: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return frames.removeValue(forKey: identifier)?.originalFrame
    }

    func removeStoredFrame(for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        frames.removeValue(forKey: identifier)
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll()
    }
}
