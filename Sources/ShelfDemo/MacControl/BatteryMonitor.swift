import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    let externalPowerConnected: Bool
    let percent: Int?

    static func capacityPercent(current: Int?, maximum: Int?) -> Int? {
        guard let current, let maximum, current >= 0, maximum > 0 else { return nil }
        return min(100, current * 100 / maximum)
    }
}

enum PowerSourceKind: Equatable {
    case internalBattery
    case other
}

enum PowerSourceConnection: Equatable {
    case externalPower
    case battery
    case offline
}

struct PowerSourceSample: Equatable {
    let kind: PowerSourceKind
    let connection: PowerSourceConnection
    let currentCapacity: Int?
    let maximumCapacity: Int?
}

extension BatterySnapshot {
    static func from(powerSources: [PowerSourceSample]) -> BatterySnapshot {
        let externalPowerConnected = powerSources.contains { $0.connection == .externalPower }
        let battery = powerSources.first { $0.kind == .internalBattery }
        return BatterySnapshot(
            externalPowerConnected: externalPowerConnected,
            percent: capacityPercent(
                current: battery?.currentCapacity,
                maximum: battery?.maximumCapacity
            )
        )
    }
}

@MainActor
protocol BatteryMonitoring: AnyObject {
    var onChange: ((BatterySnapshot) -> Void)? { get set }
    var snapshot: BatterySnapshot? { get }
    func start()
    func stop()
}

/// Uses the system power-source change notification, with a low-rate fallback
/// poll to recover if the run-loop notification source becomes unavailable.
@MainActor
final class IOKitBatteryMonitor: BatteryMonitoring {
    var onChange: ((BatterySnapshot) -> Void)?
    private(set) var snapshot: BatterySnapshot?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackTimer: Timer?

    func start() {
        guard runLoopSource == nil else { refresh(); return }
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<IOKitBatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        runLoopSource = IOPSNotificationCreateRunLoopSource(
            callback,
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue()
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        onChange = nil
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as NSDictionary? as? [String: Any]
        }
        let samples = descriptions.map { description in
            let kind: PowerSourceKind =
                (description[kIOPSTypeKey] as? String) == (kIOPSInternalBatteryType as String)
                ? .internalBattery : .other
            let state = description[kIOPSPowerSourceStateKey] as? String
            let connection: PowerSourceConnection
            switch state {
            case "AC Power": connection = .externalPower
            case "Battery Power": connection = .battery
            default: connection = .offline
            }
            return PowerSourceSample(
                kind: kind,
                connection: connection,
                currentCapacity: description[kIOPSCurrentCapacityKey] as? Int,
                maximumCapacity: description[kIOPSMaxCapacityKey] as? Int
            )
        }
        let newValue = BatterySnapshot.from(powerSources: samples)
        guard newValue != snapshot else { return }
        snapshot = newValue
        onChange?(newValue)
    }

    isolated deinit {
        fallbackTimer?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }
}
