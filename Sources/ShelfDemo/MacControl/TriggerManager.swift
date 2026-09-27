import Foundation

/// Reconciles only the assertions owned by each automation trigger.
/// Manual sessions are independent and remain active when a trigger stops.
@MainActor
final class TriggerManager {
    private let sessions: KeepAwakeSessionManager
    private(set) var batteryCutoffLatched = false

    init(sessions: KeepAwakeSessionManager) {
        self.sessions = sessions
    }

    func update(
        power: BatterySnapshot?,
        lowBatteryProtectionEnabled: Bool,
        batteryThreshold: Int,
        powerAdapterTriggerEnabled: Bool,
        selectedApplicationBundleIDs: Set<String>,
        runningApplicationBundleIDs: Set<String>,
        behavior: KeepAwakeBehavior
    ) {
        if let power, lowBatteryProtectionEnabled,
           !power.externalPowerConnected,
           let percent = power.percent,
           percent < batteryThreshold {
            batteryCutoffLatched = true
            sessions.stopAll()
        } else if !lowBatteryProtectionEnabled
                    || power?.externalPowerConnected == true
                    || power?.percent.map({ $0 >= batteryThreshold }) == true {
            batteryCutoffLatched = false
        }

        guard !batteryCutoffLatched else { return }

        reconcile(
            owner: .powerAdapter,
            shouldRun: powerAdapterTriggerEnabled && (power?.externalPowerConnected == true),
            behavior: behavior
        )

        let desiredApps = selectedApplicationBundleIDs.intersection(runningApplicationBundleIDs)
        let activeAppOwners = sessions.sessions.keys.compactMap { owner -> String? in
            guard case .application(let bundleID) = owner else { return nil }
            return bundleID
        }
        for bundleID in Set(activeAppOwners).subtracting(desiredApps) {
            sessions.stop(owner: .application(bundleIdentifier: bundleID))
        }
        for bundleID in desiredApps {
            reconcile(
                owner: .application(bundleIdentifier: bundleID),
                shouldRun: true,
                behavior: behavior
            )
        }
    }

    private func reconcile(owner: KeepAwakeOwner, shouldRun: Bool, behavior: KeepAwakeBehavior) {
        if shouldRun {
            guard sessions.session(for: owner)?.behavior != behavior else { return }
            _ = sessions.start(owner: owner, behavior: behavior)
        } else {
            sessions.stop(owner: owner)
        }
    }
}
