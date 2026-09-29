import XCTest
@testable import AmorDrop

@MainActor
final class SessionStatisticsTests: XCTestCase {
    func test_statistics_persist_reload_disable_and_clear() {
        let name = "AmorDrop.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionStatistics(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1000)
        store.record(source: "Manual Keep Awake", startedAt: start, endedAt: start.addingTimeInterval(90))
        let restored = SessionStatistics(defaults: defaults)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.seconds, 90)
        XCTAssertEqual(restored.records, store.records)
        restored.enabled = false
        restored.record(source: "ignored", startedAt: start, endedAt: start.addingTimeInterval(100))
        XCTAssertEqual(restored.count, 1)
        XCTAssertFalse(SessionStatistics(defaults: defaults).enabled)
        restored.clear()
        let cleared = SessionStatistics(defaults: defaults)
        XCTAssertEqual(cleared.count, 0)
        XCTAssertEqual(cleared.seconds, 0)
        XCTAssertTrue(cleared.records.isEmpty)
    }

    func test_retention_is_bounded_without_losing_totals() {
        let name = "AmorDrop.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionStatistics(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1000)
        for _ in 0..<205 {
            store.record(source: "Manual Keep Awake", startedAt: start, endedAt: start.addingTimeInterval(60))
        }
        XCTAssertEqual(store.records.count, 200)
        XCTAssertEqual(store.count, 205)
        XCTAssertEqual(store.seconds, 12300)
        store.record(source: "invalid", startedAt: start, endedAt: start.addingTimeInterval(-1))
        XCTAssertEqual(store.count, 205)
    }

    func test_duration_options_and_countdown_format() {
        XCTAssertEqual(SessionDurationOptions.minutes, [30,60,120,180,240,360,480,720])
        XCTAssertEqual(SessionDurationOptions.clock(3661), "01:01:01")
        XCTAssertEqual(SessionDurationOptions.clock(-1), "00:00:00")
        XCTAssertEqual(SessionDurationOptions.clock(0.2), "00:00:01")
    }
}
