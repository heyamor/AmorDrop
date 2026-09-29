import XCTest
@testable import AmorDrop

@MainActor
private final class FakeKeyboardLockMonitor: KeyboardLockMonitoring {
    var hasAccessibilityPermission = true
    var hasInputMonitoringPermission = true
    var starts = 0
    var stops = 0
    var shouldFailStart = false
    var requestPermissionGrantsAccess = false
    var permissionRequests = 0
    var onUnlock: (@MainActor @Sendable () -> Void)?

    func requestAccessibilityPermission() -> Bool {
        permissionRequests += 1
        if requestPermissionGrantsAccess { hasAccessibilityPermission = true }
        return requestPermissionGrantsAccess
    }

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
        monitor.hasAccessibilityPermission = false
        let manager = KeyboardLockManager(monitor: monitor)

        manager.beginLockRequest()

        XCTAssertEqual(manager.state, .permissionRequired)
        XCTAssertEqual(monitor.permissionRequests, 1)
        XCTAssertEqual(monitor.starts, 0)
    }

    func test_permission_request_can_grant_access_before_countdown() {
        let monitor = FakeKeyboardLockMonitor()
        monitor.hasAccessibilityPermission = false
        monitor.requestPermissionGrantsAccess = true
        let manager = KeyboardLockManager(monitor: monitor)

        manager.beginLockRequest()

        XCTAssertEqual(manager.state, .countingDown(3))
        XCTAssertEqual(monitor.permissionRequests, 1)
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
    func test_permission_revoked_during_countdown_never_starts_tap() {
        let monitor = FakeKeyboardLockMonitor()
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        monitor.hasAccessibilityPermission = false
        manager.advanceCountdown()
        manager.advanceCountdown()
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .permissionRequired)
        XCTAssertEqual(monitor.starts, 0)
    }

    func test_retry_after_accessibility_grant_does_not_require_app_restart() {
        let monitor = FakeKeyboardLockMonitor()
        monitor.hasAccessibilityPermission = false
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        XCTAssertEqual(manager.state, .permissionRequired)
        manager.returnToIdle()
        monitor.hasAccessibilityPermission = true
        manager.beginLockRequest()
        manager.advanceCountdown()
        manager.advanceCountdown()
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .locked)
        XCTAssertEqual(monitor.starts, 1)
    }

    func test_cancel_countdown_cannot_lock_on_late_tick() {
        let monitor = FakeKeyboardLockMonitor()
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        manager.shutdown()
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(monitor.starts, 0)
    }

    func test_incomplete_tap_with_stale_input_permission_guides_to_input_monitoring() {
        let monitor = FakeKeyboardLockMonitor()
        monitor.hasInputMonitoringPermission = false
        monitor.shouldFailStart = true
        let manager = KeyboardLockManager(monitor: monitor)
        manager.beginLockRequest()
        manager.advanceCountdown()
        manager.advanceCountdown()
        manager.advanceCountdown()
        XCTAssertEqual(manager.state, .permissionRequired)
        XCTAssertEqual(manager.permissionSettingsTitleKey, "Open Input Monitoring Settings")
        XCTAssertEqual(monitor.stops, 1)
    }

}
