import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let macControlPreferencesDidChange = Notification.Name("AmorDropMacControlPreferencesDidChange")
}

enum MacControlPreference {
    static let allowDisplaySleep = "macControl.allowDisplaySleep"
    static let lowBatteryProtection = "macControl.lowBatteryProtection"
    static let lowBatteryThreshold = "macControl.lowBatteryThreshold"
    static let powerAdapterTrigger = "macControl.powerAdapterTrigger"
    static let selectedAppBundleIdentifiers = "macControl.selectedAppBundleIdentifiers"

    static func publishChanges() {
        NotificationCenter.default.post(name: .macControlPreferencesDidChange, object: nil)
    }
}

@MainActor
final class MacControlCoordinator: ObservableObject {
    let keepAwake = KeepAwakeSessionManager()
    let keyboardLock = KeyboardLockManager()
    let closedLid = ClosedLidManager()

    @Published private(set) var battery: BatterySnapshot?

    private let batteryMonitor: BatteryMonitoring
    private lazy var triggerManager = TriggerManager(sessions: keepAwake)
    private var workspaceObservers: [NSObjectProtocol] = []
    private var preferenceObserver: NSObjectProtocol?
    private var started = false

    var keepAwakeBlockedByLowBattery: Bool { triggerManager.batteryCutoffLatched }

    init(batteryMonitor: BatteryMonitoring? = nil) {
        self.batteryMonitor = batteryMonitor ?? IOKitBatteryMonitor()
    }

    func start() {
        guard !started else { return }
        started = true
        closedLid.refreshStatus()
        batteryMonitor.onChange = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.battery = snapshot
                self?.reconcileTriggers()
            }
        }
        batteryMonitor.start()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcileTriggers() }
            })
        }
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .macControlPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileTriggers() }
        }
        reconcileTriggers()
    }

    @discardableResult
    func startManualKeepAwake(duration: KeepAwakeDuration) -> Bool {
        if triggerManager.batteryCutoffLatched { return false }
        let allowDisplaySleep = UserDefaults.standard.object(forKey: MacControlPreference.allowDisplaySleep) as? Bool ?? true
        let behavior: KeepAwakeBehavior = allowDisplaySleep
            ? .allowDisplaySleep : .keepDisplayAwake
        return keepAwake.start(owner: .manual, behavior: behavior, duration: duration)
    }

    func endManualKeepAwake() {
        keepAwake.stop(owner: .manual)
    }

    func requestKeyboardLock() {
        keyboardLock.beginLockRequest()
    }

    func runningApplications() -> [RunningAppChoice] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleIdentifier }
            .compactMap { application -> RunningAppChoice? in
                guard let bundleIdentifier = application.bundleIdentifier else { return nil }
                return RunningAppChoice(
                    bundleIdentifier: bundleIdentifier,
                    name: application.localizedName ?? bundleIdentifier
                )
            }
        return Dictionary(running.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func shutdown() {
        guard started else { return }
        started = false
        batteryMonitor.stop()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
            self.preferenceObserver = nil
        }
        keyboardLock.shutdown()
        closedLid.shutdown()
        keepAwake.stopAll()
    }

    private func reconcileTriggers() {
        guard started else { return }
        let defaults = UserDefaults.standard
        let allowDisplaySleep = defaults.object(forKey: MacControlPreference.allowDisplaySleep) as? Bool ?? true
        let behavior: KeepAwakeBehavior = allowDisplaySleep ? .allowDisplaySleep : .keepDisplayAwake
        _ = keepAwake.updateBehavior(for: .manual, to: behavior)
        let selectedApps = Set(defaults.stringArray(forKey: MacControlPreference.selectedAppBundleIdentifiers) ?? [])
        let runningApps = Set(runningApplications().map(\.bundleIdentifier))
        triggerManager.update(
            power: battery,
            lowBatteryProtectionEnabled: defaults.object(forKey: MacControlPreference.lowBatteryProtection) as? Bool ?? true,
            batteryThreshold: defaults.object(forKey: MacControlPreference.lowBatteryThreshold) as? Int ?? 20,
            powerAdapterTriggerEnabled: defaults.bool(forKey: MacControlPreference.powerAdapterTrigger),
            selectedApplicationBundleIDs: selectedApps,
            runningApplicationBundleIDs: runningApps,
            behavior: behavior
        )
    }

    isolated deinit {
        batteryMonitor.stop()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        keyboardLock.shutdown()
        closedLid.shutdown()
        keepAwake.stopAll()
    }
}

struct RunningAppChoice: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}
