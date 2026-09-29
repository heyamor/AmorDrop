import IOKit.pwr_mgt
import XCTest
@testable import AmorDrop

@MainActor
private final class FakePowerAssertionController: PowerAssertionControlling {
    var nextID: IOPMAssertionID = 1
    var created: [(id: IOPMAssertionID, type: String, name: String)] = []
    var released: [IOPMAssertionID] = []
    var shouldFail = false

    func create(type: String, name: String) -> IOPMAssertionID? {
        guard !shouldFail else { return nil }
        let id = nextID
        nextID += 1
        created.append((id, type, name))
        return id
    }

    func release(_ id: IOPMAssertionID) { released.append(id) }
}

@MainActor
final class KeepAwakeSessionTests: XCTestCase {
    func test_allowDisplaySleep_uses_idle_system_assertion() {
        let assertions = FakePowerAssertionController()
        let manager = KeepAwakeSessionManager(assertions: assertions)

        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep))

        XCTAssertEqual(assertions.created.first?.type, kIOPMAssertionTypePreventUserIdleSystemSleep as String)
        XCTAssertEqual(manager.session(for: .manual)?.deadline, nil)
    }

    func test_keepDisplayAwake_uses_display_assertion() {
        let assertions = FakePowerAssertionController()
        let manager = KeepAwakeSessionManager(assertions: assertions)

        XCTAssertTrue(manager.start(owner: .manual, behavior: .keepDisplayAwake))

        XCTAssertEqual(assertions.created.first?.type, kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
    }

    func test_timed_session_expires_and_releases_its_assertion() {
        let assertions = FakePowerAssertionController()
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = KeepAwakeSessionManager(assertions: assertions, now: { now })

        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep, duration: .minutes(30)))
        now.addTimeInterval(30 * 60)
        manager.expireDueSessions()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(assertions.released, [1])
    }

    func test_updating_behavior_replaces_assertion_without_extending_deadline() {
        let assertions = FakePowerAssertionController()
        let now = Date(timeIntervalSince1970: 1_000)
        let manager = KeepAwakeSessionManager(assertions: assertions, now: { now })
        XCTAssertTrue(manager.start(
            owner: .manual,
            behavior: .allowDisplaySleep,
            duration: .minutes(30)
        ))
        let originalDeadline = manager.session(for: .manual)?.deadline

        XCTAssertTrue(manager.updateBehavior(for: .manual, to: .keepDisplayAwake))

        XCTAssertEqual(assertions.created.count, 2)
        XCTAssertEqual(assertions.created[1].type, kIOPMAssertionTypePreventUserIdleDisplaySleep as String)
        XCTAssertEqual(assertions.released, [1])
        XCTAssertEqual(manager.session(for: .manual)?.assertionID, 2)
        XCTAssertEqual(manager.session(for: .manual)?.deadline, originalDeadline)
    }

    func test_failed_behavior_update_keeps_existing_assertion_active() {
        let assertions = FakePowerAssertionController()
        let manager = KeepAwakeSessionManager(assertions: assertions)
        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep))
        assertions.shouldFail = true

        XCTAssertFalse(manager.updateBehavior(for: .manual, to: .keepDisplayAwake))

        XCTAssertEqual(manager.session(for: .manual)?.assertionID, 1)
        XCTAssertEqual(manager.session(for: .manual)?.behavior, .allowDisplaySleep)
        XCTAssertTrue(assertions.released.isEmpty)
    }

    func test_until_date_expiry_and_invalid_past_date() {
        let assertions = FakePowerAssertionController()
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = KeepAwakeSessionManager(assertions: assertions, now: { now })
        let finish = now.addingTimeInterval(60)

        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep, duration: .until(finish)))
        XCTAssertFalse(manager.start(owner: .powerAdapter, behavior: .allowDisplaySleep, duration: .until(now)))
        now = finish
        manager.expireDueSessions()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(assertions.released, [1])
    }

    func test_replacing_and_stopping_one_owner_does_not_release_another() {
        let assertions = FakePowerAssertionController()
        let manager = KeepAwakeSessionManager(assertions: assertions)
        let application = KeepAwakeOwner.application(bundleIdentifier: "com.example.editor")

        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep))
        XCTAssertTrue(manager.start(owner: application, behavior: .keepDisplayAwake))
        XCTAssertTrue(manager.start(owner: application, behavior: .keepDisplayAwake))
        XCTAssertEqual(assertions.released, [2])
        XCTAssertTrue(manager.stop(owner: application))

        XCTAssertTrue(manager.isActive)
        XCTAssertNotNil(manager.session(for: .manual))
        XCTAssertEqual(assertions.released, [2, 3])
    }

    func test_assertion_failure_does_not_create_a_session() {
        let assertions = FakePowerAssertionController()
        assertions.shouldFail = true
        let manager = KeepAwakeSessionManager(assertions: assertions)

        XCTAssertFalse(manager.start(owner: .manual, behavior: .allowDisplaySleep))
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(assertions.released.isEmpty)
    }

    func test_stopping_all_releases_every_assertion() {
        let assertions = FakePowerAssertionController()
        let manager = KeepAwakeSessionManager(assertions: assertions)
        let application = KeepAwakeOwner.application(bundleIdentifier: "com.example.editor")
        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep))
        XCTAssertTrue(manager.start(owner: application, behavior: .keepDisplayAwake))

        manager.stopAll()
        manager.stopAll()

        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(Set(assertions.released), Set([1, 2]))
    }
    func test_timer_keeps_ticking_after_first_non_expiring_tick() async throws {
        let assertions = FakePowerAssertionController()
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = KeepAwakeSessionManager(assertions: assertions, now: { now })
        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep, duration: .minutes(1)))
        now.addTimeInterval(10)
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(manager.currentTime, now)
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.hasScheduledTick)
        now.addTimeInterval(51)
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(assertions.released, [1])
        XCTAssertFalse(manager.hasScheduledTick)
    }

    func test_delayed_expiry_records_deadline_not_late_wakeup_time() {
        let assertions = FakePowerAssertionController()
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = KeepAwakeSessionManager(assertions: assertions, now: { now })
        var ends: [Date] = []
        manager.onSessionEnded = { _, end in ends.append(end) }
        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep, duration: .minutes(1)))
        now.addTimeInterval(300)
        manager.expireDueSessions()
        manager.expireDueSessions()
        XCTAssertEqual(ends, [Date(timeIntervalSince1970: 1060)])
        XCTAssertEqual(assertions.released, [1])
    }

    func test_behavior_change_preserves_start_and_does_not_split_statistics() {
        let assertions = FakePowerAssertionController()
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = KeepAwakeSessionManager(assertions: assertions, now: { now })
        var starts: [Date] = []
        manager.onSessionEnded = { session, _ in starts.append(session.startedAt) }
        XCTAssertTrue(manager.start(owner: .manual, behavior: .allowDisplaySleep, duration: .minutes(5)))
        now.addTimeInterval(60)
        XCTAssertTrue(manager.updateBehavior(for: .manual, to: .keepDisplayAwake))
        XCTAssertTrue(starts.isEmpty)
        XCTAssertEqual(manager.session(for: .manual)?.startedAt, Date(timeIntervalSince1970: 1000))
        manager.stopAll()
        XCTAssertEqual(starts, [Date(timeIntervalSince1970: 1000)])
    }

}
