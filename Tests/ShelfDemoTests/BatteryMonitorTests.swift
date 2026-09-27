import XCTest
@testable import ShelfDemo

final class BatteryMonitorTests: XCTestCase {
    func test_reports_external_power_and_internal_battery_percentage() {
        let snapshot = BatterySnapshot.from(powerSources: [
            PowerSourceSample(
                kind: .internalBattery,
                connection: .externalPower,
                currentCapacity: 40,
                maximumCapacity: 100
            )
        ])
        XCTAssertTrue(snapshot.externalPowerConnected)
        XCTAssertEqual(snapshot.percent, 40)
    }

    func test_does_not_treat_a_ups_as_the_macbook_battery() {
        let snapshot = BatterySnapshot.from(powerSources: [
            PowerSourceSample(
                kind: .other,
                connection: .battery,
                currentCapacity: 4,
                maximumCapacity: 10
            )
        ])
        XCTAssertFalse(snapshot.externalPowerConnected)
        XCTAssertNil(snapshot.percent)
    }

    func test_missing_and_invalid_capacity_are_unknown() {
        XCTAssertNil(BatterySnapshot.capacityPercent(current: 20, maximum: nil))
        XCTAssertNil(BatterySnapshot.capacityPercent(current: -1, maximum: 100))
        XCTAssertNil(BatterySnapshot.capacityPercent(current: 20, maximum: 0))
    }

    func test_capacity_is_rounded_down_and_clamped() {
        XCTAssertEqual(BatterySnapshot.capacityPercent(current: 19, maximum: 100), 19)
        XCTAssertEqual(BatterySnapshot.capacityPercent(current: 101, maximum: 100), 100)
    }
}
