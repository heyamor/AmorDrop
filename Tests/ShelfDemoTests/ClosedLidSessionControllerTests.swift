import ClosedLidCore
import XCTest

private final class FakeSleepSettingController: SleepSettingControlling {
    var value: Bool
    var readFails = false
    var nextSetFails = false

    init(value: Bool = false) { self.value = value }

    func readSleepDisabled() throws -> Bool {
        if readFails { throw CocoaError(.fileReadUnknown) }
        return value
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        if nextSetFails {
            nextSetFails = false
            throw CocoaError(.fileWriteUnknown)
        }
        value = disabled
    }
}

private final class FakeClosedLidStateStore: ClosedLidStateStoring {
    var state: ClosedLidSessionState?
    var shouldFailSave = false
    var shouldFailClear = false

    func load() throws -> ClosedLidSessionState? { state }
    func save(_ state: ClosedLidSessionState) throws {
        if shouldFailSave { throw CocoaError(.fileWriteUnknown) }
        self.state = state
    }
    func clear() throws {
        if shouldFailClear { throw CocoaError(.fileWriteUnknown) }
        state = nil
    }
}

final class ClosedLidSessionControllerTests: XCTestCase {
    func test_start_snapshots_before_enabling_and_stop_restores_original_value() throws {
        let settings = FakeSleepSettingController(value: false)
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)

        let state = try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20)

        XCTAssertFalse(state.originalSleepDisabled)
        XCTAssertTrue(settings.value)
        XCTAssertNotNil(store.state)

        try controller.stopAndRestore()

        XCTAssertFalse(settings.value)
        XCTAssertNil(store.state)
    }

    func test_originallyDisabledSystemSleepIsRestoredAsDisabled() throws {
        let settings = FakeSleepSettingController(value: true)
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)

        _ = try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20)
        try controller.stopAndRestore()

        XCTAssertTrue(settings.value)
        XCTAssertNil(store.state)
    }

    func test_recovery_restores_stale_session_after_helper_restart() throws {
        let settings = FakeSleepSettingController(value: true)
        let store = FakeClosedLidStateStore()
        store.state = ClosedLidSessionState(
            originalSleepDisabled: false,
            lowBatteryProtectionEnabled: true,
            lowBatteryThreshold: 20
        )
        let controller = ClosedLidSessionController(settings: settings, store: store)

        try controller.recoverStaleSession()

        XCTAssertFalse(settings.value)
        XCTAssertNil(store.state)
    }

    func test_low_battery_ends_session_only_on_battery_at_or_below_threshold() throws {
        let settings = FakeSleepSettingController()
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)
        _ = try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20)

        XCTAssertFalse(try controller.endForLowBatteryIfNeeded(isOnBattery: true, percent: 21))
        XCTAssertFalse(try controller.endForLowBatteryIfNeeded(isOnBattery: false, percent: 5))
        XCTAssertTrue(settings.value)
        XCTAssertTrue(try controller.endForLowBatteryIfNeeded(isOnBattery: true, percent: 20))
        XCTAssertFalse(settings.value)
        XCTAssertNil(store.state)
    }

    func test_unknown_battery_state_ends_session_when_protection_is_enabled() throws {
        let settings = FakeSleepSettingController()
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)
        _ = try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20)

        XCTAssertTrue(try controller.endForLowBatteryIfNeeded(isOnBattery: nil, percent: nil))
        XCTAssertFalse(settings.value)
        XCTAssertNil(store.state)
    }

    func test_low_battery_protection_can_be_disabled_for_session() throws {
        let settings = FakeSleepSettingController()
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)
        _ = try controller.start(lowBatteryProtectionEnabled: false, lowBatteryThreshold: 20)

        XCTAssertFalse(try controller.endForLowBatteryIfNeeded(isOnBattery: true, percent: 1))
        XCTAssertTrue(settings.value)
    }

    func test_snapshot_failure_does_not_write_or_change_system_setting() {
        let settings = FakeSleepSettingController(value: false)
        settings.readFails = true
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)

        XCTAssertThrowsError(try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20))
        XCTAssertFalse(settings.value)
        XCTAssertNil(store.state)
    }

    func test_state_write_failure_does_not_change_system_setting() {
        let settings = FakeSleepSettingController(value: false)
        let store = FakeClosedLidStateStore()
        store.shouldFailSave = true
        let controller = ClosedLidSessionController(settings: settings, store: store)

        XCTAssertThrowsError(try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20))
        XCTAssertFalse(settings.value)
    }

    func test_failed_restore_keeps_recovery_record() throws {
        let settings = FakeSleepSettingController(value: false)
        let store = FakeClosedLidStateStore()
        let controller = ClosedLidSessionController(settings: settings, store: store)
        _ = try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 20)
        settings.nextSetFails = true

        XCTAssertThrowsError(try controller.stopAndRestore())
        XCTAssertNotNil(store.state)
    }

    func test_cannot_overwrite_existing_recovery_snapshot() throws {
        let settings = FakeSleepSettingController(value: false)
        let original = ClosedLidSessionState(
            originalSleepDisabled: true,
            lowBatteryProtectionEnabled: true,
            lowBatteryThreshold: 20
        )
        let store = FakeClosedLidStateStore()
        store.state = original
        let controller = ClosedLidSessionController(settings: settings, store: store)

        XCTAssertThrowsError(try controller.start(lowBatteryProtectionEnabled: true, lowBatteryThreshold: 25))
        XCTAssertEqual(store.state, original)
        XCTAssertFalse(settings.value)
    }
}
