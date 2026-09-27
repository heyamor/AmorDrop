import XCTest
@testable import ShelfDemo

@MainActor
private final class TriggerTestPowerAssertions: PowerAssertionControlling {
    var created: [UInt32: String] = [:]
    var released: Set<UInt32> = []
    private var nextID: UInt32 = 1

    func create(type: String, name: String) -> UInt32? {
        let id = nextID
        nextID += 1
        created[id] = name
        return id
    }

    func release(_ id: UInt32) { released.insert(id) }
}

@MainActor
final class TriggerManagerTests: XCTestCase {
    private func makeManagers() -> (TriggerTestPowerAssertions, KeepAwakeSessionManager, TriggerManager) {
        let power = TriggerTestPowerAssertions()
        let sessions = KeepAwakeSessionManager(assertions: power)
        return (power, sessions, TriggerManager(sessions: sessions))
    }

    private func update(
        _ triggers: TriggerManager,
        power: BatterySnapshot?,
        acEnabled: Bool = false,
        selected: Set<String> = [],
        running: Set<String> = [],
        lowProtection: Bool = false,
        threshold: Int = 20
    ) {
        triggers.update(
            power: power,
            lowBatteryProtectionEnabled: lowProtection,
            batteryThreshold: threshold,
            powerAdapterTriggerEnabled: acEnabled,
            selectedApplicationBundleIDs: selected,
            runningApplicationBundleIDs: running,
            behavior: .allowDisplaySleep
        )
    }

    func test_power_trigger_owns_and_releases_only_its_session() {
        let (_, sessions, triggers) = makeManagers()
        XCTAssertTrue(sessions.start(owner: .manual, behavior: .keepDisplayAwake))
        let ac = BatterySnapshot(externalPowerConnected: true, percent: 80)

        update(triggers, power: ac, acEnabled: true)
        XCTAssertNotNil(sessions.session(for: .powerAdapter))
        update(triggers, power: BatterySnapshot(externalPowerConnected: false, percent: 80), acEnabled: true)

        XCTAssertNil(sessions.session(for: .powerAdapter))
        XCTAssertNotNil(sessions.session(for: .manual))
    }

    func test_power_trigger_default_off_does_not_start() {
        let (_, sessions, triggers) = makeManagers()
        update(triggers, power: BatterySnapshot(externalPowerConnected: true, percent: 100))
        XCTAssertNil(sessions.session(for: .powerAdapter))
    }

    func test_application_trigger_starts_and_stops_by_bundle_id() {
        let (_, sessions, triggers) = makeManagers()
        let editor = "com.example.editor"

        update(triggers, power: nil, selected: [editor], running: [editor])
        XCTAssertNotNil(sessions.session(for: .application(bundleIdentifier: editor)))
        update(triggers, power: nil, selected: [editor], running: [])

        XCTAssertNil(sessions.session(for: .application(bundleIdentifier: editor)))
    }

    func test_application_trigger_removal_keeps_manual_and_other_app_sessions() {
        let (_, sessions, triggers) = makeManagers()
        let editor = "com.example.editor"
        let render = "com.example.render"
        XCTAssertTrue(sessions.start(owner: .manual, behavior: .allowDisplaySleep))
        XCTAssertTrue(sessions.start(owner: .application(bundleIdentifier: render), behavior: .allowDisplaySleep))
        update(triggers, power: nil, selected: [editor, render], running: [editor, render])

        update(triggers, power: nil, selected: [render], running: [editor, render])

        XCTAssertNotNil(sessions.session(for: .manual))
        XCTAssertNotNil(sessions.session(for: .application(bundleIdentifier: render)))
        XCTAssertNil(sessions.session(for: .application(bundleIdentifier: editor)))
    }

    func test_low_battery_stops_manual_and_all_triggers_then_latches_until_recovery() {
        let (_, sessions, triggers) = makeManagers()
        let editor = "com.example.editor"
        XCTAssertTrue(sessions.start(owner: .manual, behavior: .allowDisplaySleep))
        update(triggers, power: BatterySnapshot(externalPowerConnected: true, percent: 80), acEnabled: true)
        update(triggers, power: BatterySnapshot(externalPowerConnected: false, percent: 19), acEnabled: true, selected: [editor], running: [editor], lowProtection: true)

        XCTAssertTrue(sessions.sessions.isEmpty)
        XCTAssertTrue(triggers.batteryCutoffLatched)
        update(triggers, power: BatterySnapshot(externalPowerConnected: false, percent: 15), acEnabled: true, selected: [editor], running: [editor], lowProtection: true)
        XCTAssertTrue(sessions.sessions.isEmpty)

        update(triggers, power: BatterySnapshot(externalPowerConnected: true, percent: 15), acEnabled: true, lowProtection: true)
        XCTAssertFalse(triggers.batteryCutoffLatched)
        XCTAssertNotNil(sessions.session(for: .powerAdapter))
    }

    func test_low_battery_protection_respects_disabled_setting_and_threshold() {
        let (_, sessions, triggers) = makeManagers()
        update(triggers, power: BatterySnapshot(externalPowerConnected: false, percent: 19), lowProtection: false)
        XCTAssertFalse(triggers.batteryCutoffLatched)
        XCTAssertTrue(sessions.start(owner: .manual, behavior: .allowDisplaySleep))
        update(triggers, power: BatterySnapshot(externalPowerConnected: false, percent: 20), lowProtection: true)
        XCTAssertFalse(triggers.batteryCutoffLatched)
        XCTAssertTrue(sessions.isActive)
    }

    func test_disabling_low_battery_protection_clears_cutoff_latch() {
        let (_, sessions, triggers) = makeManagers()
        let battery = BatterySnapshot(externalPowerConnected: false, percent: 19)
        update(triggers, power: battery, lowProtection: true)
        XCTAssertTrue(triggers.batteryCutoffLatched)

        update(triggers, power: battery, selected: ["com.example.editor"], running: ["com.example.editor"])

        XCTAssertFalse(triggers.batteryCutoffLatched)
        XCTAssertNotNil(sessions.session(for: .application(bundleIdentifier: "com.example.editor")))
    }
}
