import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

enum KeepAwakeBehavior: String, CaseIterable, Identifiable {
    case allowDisplaySleep
    case keepDisplayAwake

    var id: String { rawValue }

    var assertionType: String {
        switch self {
        case .allowDisplaySleep:
            return kIOPMAssertionTypePreventUserIdleSystemSleep as String
        case .keepDisplayAwake:
            return kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        }
    }
}

enum KeepAwakeOwner: Hashable {
    case manual
    case powerAdapter
    case application(bundleIdentifier: String)
}

enum KeepAwakeDuration: Equatable {
    case minutes(Int)
    case until(Date)
    case indefinite

    func deadline(startedAt: Date) -> Date? {
        switch self {
        case .minutes(let minutes):
            guard minutes > 0 else { return startedAt }
            return startedAt.addingTimeInterval(TimeInterval(minutes) * 60)
        case .until(let date):
            return date
        case .indefinite:
            return nil
        }
    }
}

struct KeepAwakeSession: Equatable {
    let owner: KeepAwakeOwner
    let behavior: KeepAwakeBehavior
    let startedAt: Date
    let deadline: Date?
    let assertionID: IOPMAssertionID
}

@MainActor
protocol PowerAssertionControlling: AnyObject {
    func create(type: String, name: String) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

@MainActor
final class IOKitPowerAssertionController: PowerAssertionControlling {
    func create(type: String, name: String) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func release(_ id: IOPMAssertionID) {
        IOPMAssertionRelease(id)
    }
}

/// Holds one separately owned IOKit assertion per manual or automated request.
/// Releasing an app/power trigger can never release a manual user's session.
@MainActor
final class KeepAwakeSessionManager: ObservableObject {
    @Published private(set) var sessions: [KeepAwakeOwner: KeepAwakeSession] = [:]
    @Published private(set) var currentTime = Date()

    private let assertions: PowerAssertionControlling
    private let now: () -> Date
    private var expiryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    var onSessionEnded: ((KeepAwakeSession, Date) -> Void)?
    var hasScheduledTick: Bool { expiryTimer?.isValid == true }


    init(
        assertions: PowerAssertionControlling? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.assertions = assertions ?? IOKitPowerAssertionController()
        self.now = now
        currentTime = now()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.expireDueSessions() }
        }
    }

    var isActive: Bool { !sessions.isEmpty }

    func session(for owner: KeepAwakeOwner) -> KeepAwakeSession? {
        sessions[owner]
    }

    @discardableResult
    func start(
        owner: KeepAwakeOwner,
        behavior: KeepAwakeBehavior,
        duration: KeepAwakeDuration = .indefinite
    ) -> Bool {
        let startedAt = now()
        let deadline = duration.deadline(startedAt: startedAt)
        guard deadline.map({ $0 > startedAt }) ?? true,
              let assertionID = assertions.create(
                type: behavior.assertionType,
                name: "AmorDrop \(owner.assertionLabel)"
              ) else {
            return false
        }

        stop(owner: owner)
        sessions[owner] = KeepAwakeSession(
            owner: owner,
            behavior: behavior,
            startedAt: startedAt,
            deadline: deadline,
            assertionID: assertionID
        )
        updateExpirationTimer()
        return true
    }

    @discardableResult
    func stop(owner: KeepAwakeOwner) -> Bool {
        guard let session = sessions.removeValue(forKey: owner) else { return false }
        assertions.release(session.assertionID)
        onSessionEnded?(session, min(now(), session.deadline ?? now()))
        updateExpirationTimer()
        return true
    }

    /// Swaps an active owner's assertion without extending its original
    /// deadline. Used when the user changes the display-sleep preference
    /// during an existing manual session.
    @discardableResult
    func updateBehavior(for owner: KeepAwakeOwner, to behavior: KeepAwakeBehavior) -> Bool {
        guard let existing = sessions[owner] else { return false }
        guard existing.behavior != behavior else { return true }
        guard existing.deadline.map({ $0 > now() }) ?? true else {
            expireDueSessions()
            return false
        }
        guard let id = assertions.create(type: behavior.assertionType, name: "AmorDrop \(owner.assertionLabel)") else { return false }
        sessions[owner] = KeepAwakeSession(owner: owner, behavior: behavior,
            startedAt: existing.startedAt, deadline: existing.deadline, assertionID: id)
        assertions.release(existing.assertionID)
        return true
    }

    func stopAll() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        let current = sessions.values
        sessions.removeAll()
        current.forEach {
            assertions.release($0.assertionID)
            onSessionEnded?($0, min(now(), $0.deadline ?? now()))
        }
        currentTime = now()
    }

    /// Also called by the repeating timer and exposed internally for
    /// deterministic expiry tests with an injected clock.
    func expireDueSessions() {
        currentTime = now()
        let expiredOwners = sessions.values.compactMap { session in
            session.deadline.map { $0 <= currentTime } == true ? session.owner : nil
        }
        for owner in expiredOwners {
            _ = stop(owner: owner)
        }
        updateExpirationTimer()
    }

    func remainingTime(for owner: KeepAwakeOwner) -> TimeInterval? {
        guard let deadline = sessions[owner]?.deadline else { return nil }
        return max(0, deadline.timeIntervalSince(currentTime))
    }

    private func updateExpirationTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        currentTime = now()
        guard !sessions.isEmpty else { return }
        // Re-arm every tick, even when nothing has expired. Common modes keep
        // expiration and countdown alive while an NSMenu tracks the mouse.
        let nextDeadline = sessions.values.compactMap(\.deadline).min()
        let interval = max(0.01, min(1, nextDeadline?.timeIntervalSince(currentTime) ?? 1))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.expireDueSessions() }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    isolated deinit {
        expiryTimer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        for session in sessions.values {
            assertions.release(session.assertionID)
        }
    }
}

private extension KeepAwakeOwner {
    var assertionLabel: String {
        switch self {
        case .manual: "manual session"
        case .powerAdapter: "power adapter trigger"
        case .application(let bundleIdentifier): "app trigger \(bundleIdentifier)"
        }
    }
}
