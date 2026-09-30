import Foundation

public struct ClosedLidSessionState: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let originalSleepDisabled: Bool
    public let lowBatteryProtectionEnabled: Bool
    public let lowBatteryThreshold: Int
    public let startedAt: Date
    public let endsAt: Date?

    public init(
        schemaVersion: Int = 1,
        originalSleepDisabled: Bool,
        lowBatteryProtectionEnabled: Bool,
        lowBatteryThreshold: Int,
        startedAt: Date = Date(),
        endsAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.originalSleepDisabled = originalSleepDisabled
        self.lowBatteryProtectionEnabled = lowBatteryProtectionEnabled
        self.lowBatteryThreshold = min(100, max(0, lowBatteryThreshold))
        self.startedAt = startedAt
        self.endsAt = endsAt
    }
}

public protocol SleepSettingControlling: AnyObject {
    func readSleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
}

public protocol ClosedLidStateStoring: AnyObject {
    func load() throws -> ClosedLidSessionState?
    func save(_ state: ClosedLidSessionState) throws
    func clear() throws
}

public enum ClosedLidSessionError: Error, Equatable, LocalizedError {
    case alreadyActive
    case invalidDuration
    case sleepSettingDidNotChange
    case sleepSettingDidNotRestore

    public var errorDescription: String? {
        switch self {
        case .alreadyActive:
            "A Closed-Lid session is already recorded. Recovery is required before starting another."
        case .invalidDuration:
            "Choose a Closed-Lid session duration from 1 second to 48 hours, or choose indefinite."
        case .sleepSettingDidNotChange:
            "macOS did not confirm the requested sleep setting."
        case .sleepSettingDidNotRestore:
            "macOS did not confirm restoration of the original sleep setting."
        }
    }
}

/// Writes a recovery record before changing the system setting. If the daemon
/// crashes between those two operations, its next launch restores the saved
/// value. The controller never clears a record until restoration is verified.
public final class ClosedLidSessionController {
    private let settings: SleepSettingControlling
    private let store: ClosedLidStateStoring
    private let now: () -> Date

    public init(
        settings: SleepSettingControlling,
        store: ClosedLidStateStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.store = store
        self.now = now
    }

    public var isActive: Bool {
        do { return try store.load() != nil }
        catch { return false }
    }

    @discardableResult
    public func start(
        lowBatteryProtectionEnabled: Bool,
        lowBatteryThreshold: Int,
        durationSeconds: TimeInterval? = nil
    ) throws -> ClosedLidSessionState {
        guard try store.load() == nil else { throw ClosedLidSessionError.alreadyActive }
        if let durationSeconds,
           (!durationSeconds.isFinite || durationSeconds < 1 || durationSeconds > 48 * 60 * 60) {
            throw ClosedLidSessionError.invalidDuration
        }

        let original = try settings.readSleepDisabled()
        let startedAt = now()
        let state = ClosedLidSessionState(
            originalSleepDisabled: original,
            lowBatteryProtectionEnabled: lowBatteryProtectionEnabled,
            lowBatteryThreshold: lowBatteryThreshold,
            startedAt: startedAt,
            endsAt: durationSeconds.map { startedAt.addingTimeInterval($0) }
        )

        // A saved record means recovery must run even if the process exits
        // before or during the pmset write.
        try store.save(state)
        do {
            try settings.setSleepDisabled(true)
            guard try settings.readSleepDisabled() else {
                throw ClosedLidSessionError.sleepSettingDidNotChange
            }
            return state
        } catch {
            // Keep the state file if restoration cannot be confirmed. The
            // next daemon launch will retry instead of losing the snapshot.
            do {
                try settings.setSleepDisabled(original)
                guard try settings.readSleepDisabled() == original else {
                    throw ClosedLidSessionError.sleepSettingDidNotRestore
                }
                try store.clear()
            } catch {
                throw error
            }
            throw error
        }
    }

    public func stopAndRestore() throws {
        guard let state = try store.load() else { return }
        try settings.setSleepDisabled(state.originalSleepDisabled)
        guard try settings.readSleepDisabled() == state.originalSleepDisabled else {
            throw ClosedLidSessionError.sleepSettingDidNotRestore
        }
        try store.clear()
    }

    /// Called before the helper begins accepting IPC and after an unexpected
    /// termination or reboot. A malformed or unreadable record is an error;
    /// callers must not overwrite it with a new session.
    public func recoverStaleSession() throws {
        try stopAndRestore()
    }

    public func endIfExpired() throws -> Bool {
        guard let state = try store.load(),
              let endsAt = state.endsAt,
              endsAt <= now() else {
            return false
        }
        try stopAndRestore()
        return true
    }

    public func endForLowBatteryIfNeeded(isOnBattery: Bool?, percent: Int?) throws -> Bool {
        guard let state = try store.load(), state.lowBatteryProtectionEnabled else {
            return false
        }
        // If the helper cannot establish whether the Mac is on external power
        // or read a battery percentage, fail closed and restore normal sleep.
        guard let isOnBattery else {
            try stopAndRestore()
            return true
        }
        guard isOnBattery else { return false }
        guard let percent, percent > state.lowBatteryThreshold else {
            try stopAndRestore()
            return true
        }
        return false
    }
}

public final class PropertyListClosedLidStateStore: ClosedLidStateStoring {
    public let url: URL
    private let fileManager: FileManager

    public init(
        url: URL = URL(fileURLWithPath: "/var/db/com.amor.personal.amordrop.closed-lid-state.plist"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
    }

    public func load() throws -> ClosedLidSessionState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
            throw CocoaError(.fileReadNoPermission)
        }
        let data = try Data(contentsOf: url)
        let state = try PropertyListDecoder().decode(ClosedLidSessionState.self, from: data)
        guard state.schemaVersion == 1,
              (0...100).contains(state.lowBatteryThreshold) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return state
    }

    public func save(_ state: ClosedLidSessionState) throws {
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

@objc public protocol ClosedLidHelperXPCProtocol {
    func startSession(
        lowBatteryProtectionEnabled: Bool,
        lowBatteryThreshold: Int,
        durationSeconds: Int64,
        reply: @escaping (Bool, Double, String?) -> Void
    )
    func stopSession(reply: @escaping (Bool, String?) -> Void)
    // Preserve the original selectors and reply ABI for existing app/helper versions.
    func startSession(lowBatteryProtectionEnabled: Bool, lowBatteryThreshold: Int,
                      reply: @escaping (Bool, String?) -> Void)
    func getSessionStatus(reply: @escaping (Bool, String?) -> Void)
    func getTimedSessionStatus(reply: @escaping (Bool, Double, String?) -> Void)
}
