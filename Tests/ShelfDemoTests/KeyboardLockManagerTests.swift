import XCTest
@testable import ShelfDemo

@MainActor
private final class FakeKeyboardLockMonitor: KeyboardLockMonitoring {
    var hasListenPermission = true
    var starts = 0
    var stops = 0
    var shouldFailStart = false
    var onUnlock: (@MainActor @Sendable () -> Void)?

    func start(onUnlock: @escaping @MainActor @Sendable () -> Void) -> Bool {
        starts += 1
        self.onUnlock = onUnlock
        return !shouldFailStart
    }

    func stop() { stops += 1 }
}

@MainActor
final class KeyboardLockManagerTests: XCTestCase {
    func test_permission_is_checked_before_countdown_and_tap_creation() {
        let monitor = FakeKeyboardLockMonitor()
        monitor.hasListenPermission = false
        let manager = KeyboardLockManager(monitor: monitor)

        manager.beginLockRequest()

        XCTAssertEqual(manager.state, .permissionRequired)
        XCTAssertEqual(monitor.starts, 0)
    }

    func test_countdown_runs_three_two_one_before_locking() {
        let monitor = FakeKeyboardLockMonitor()
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        XCTAssertEqual(manager.state, .countingDown(3))
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .countingDown(2))
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .countingDown(1))
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .locked)
        XCTAssertEqual(monitor.starts, 1)
    }

    func test_manual_unlock_stops_event_tap() {
        let monitor = FakeKeyboardLockMonitor()
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        manager.advanceCountdown()
        manager.advanceCountdown()
        manager.advanceCountdown()

        manager.unlock()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(monitor.stops, 1)
    }

    func test_event_tap_creation_failure_never_enters_locked_state() {
        let monitor = FakeKeyboardLockMonitor()
        monitor.shouldFailStart = true
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        manager.advanceCountdown()
        manager.advanceCountdown()
        manager.advanceCountdown()

        XCTAssertEqual(manager.state, .unavailable)
    }

    func test_event_tap_fail_open_returns_manager_to_idle() {
        let monitor = FakeKeyboardLockMonitor()
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        manager.advanceCountdown()
        manager.advanceCountdown()
        manager.advanceCountdown()
        monitor.onUnlock?()

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(monitor.stops, 1)
    }
}
