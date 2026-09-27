import ClosedLidCore
import Combine
import Foundation
import ServiceManagement

@MainActor
final class ClosedLidManager: ObservableObject {
    @Published private(set) var registrationStatus: SMAppService.Status
    @Published private(set) var sessionActive = false
    @Published private(set) var lastError: String?

    private let service: SMAppService
    private var connection: NSXPCConnection?

    convenience init() {
        self.init(service: SMAppService.daemon(plistName: "com.amor.personal.amordrop.closed-lid.plist"))
    }

    init(service: SMAppService) {
        self.service = service
        self.registrationStatus = service.status
    }

    static let launchDaemonPlistName = "com.amor.personal.amordrop.closed-lid.plist"
    static let machServiceName = "com.amor.personal.amordrop.closed-lid"

    var isAuthorized: Bool { registrationStatus == .enabled }

    func refreshStatus() {
        registrationStatus = service.status
        guard isAuthorized else {
            sessionActive = false
            connection?.invalidate()
            connection = nil
            return
        }
        Task {
            do {
                sessionActive = try await readSessionStatus()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Requests Apple's standard LaunchDaemon approval flow. This method is
    /// only called from an explicit user action; it is never invoked at launch.
    func requestHelperAuthorization() throws {
        do {
            refreshStatus()
            if registrationStatus == .requiresApproval {
                openLoginItemsSettings()
                return
            }
            if registrationStatus == .enabled { return }
            try service.register()
            lastError = nil
            refreshStatus()
            if registrationStatus == .requiresApproval { openLoginItemsSettings() }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func unregisterHelper() async throws {
        if sessionActive { try await stopSession() }
        connection?.invalidate()
        connection = nil
        try await service.unregister()
        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func startSession(lowBatteryProtectionEnabled: Bool, threshold: Int) async throws {
        guard isAuthorized else { throw ClosedLidManagerError.authorizationRequired }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let proxy = try remoteProxy(onFailure: { error in
                    continuation.resume(throwing: error)
                })
                proxy.startSession(
                    lowBatteryProtectionEnabled: lowBatteryProtectionEnabled,
                    lowBatteryThreshold: threshold
                ) { success, message in
                    Task { @MainActor in
                        if success {
                            self.sessionActive = true
                            self.lastError = nil
                            continuation.resume()
                        } else {
                            let error = ClosedLidManagerError.helper(message ?? "Could not start Closed-Lid Mode")
                            self.lastError = error.localizedDescription
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stopSession() async throws {
        guard connection != nil else {
            sessionActive = false
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let proxy = try remoteProxy(onFailure: { error in
                    continuation.resume(throwing: error)
                })
                proxy.stopSession { success, message in
                    Task { @MainActor in
                        if success {
                            self.sessionActive = false
                            self.lastError = nil
                            continuation.resume()
                        } else {
                            let error = ClosedLidManagerError.helper(message ?? "Could not restore the original sleep setting")
                            self.lastError = error.localizedDescription
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func shutdown() {
        // The daemon restores the saved system value on XPC invalidation.
        connection?.invalidate()
        connection = nil
        sessionActive = false
    }

    private func readSessionStatus() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            do {
                let proxy = try remoteProxy(onFailure: { error in
                    continuation.resume(throwing: error)
                })
                proxy.getSessionStatus { active, message in
                    Task { @MainActor in
                        if let message {
                            continuation.resume(throwing: ClosedLidManagerError.helper(message))
                        } else {
                            continuation.resume(returning: active)
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func remoteProxy(onFailure: @escaping (Error) -> Void) throws -> ClosedLidHelperXPCProtocol {
        if connection == nil {
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: ClosedLidHelperXPCProtocol.self)
            connection.interruptionHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.sessionActive = false
                }
            }
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.sessionActive = false
                    self?.connection = nil
                }
            }
            connection.resume()
            self.connection = connection
        }
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Task { @MainActor [weak self] in self?.lastError = error.localizedDescription }
            onFailure(error)
        }) as? ClosedLidHelperXPCProtocol else {
            throw ClosedLidManagerError.connectionUnavailable
        }
        return proxy
    }
}

private enum ClosedLidManagerError: LocalizedError {
    case authorizationRequired
    case connectionUnavailable
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .authorizationRequired:
            "The Closed-Lid helper has not been approved in System Settings."
        case .connectionUnavailable:
            "AmorDrop could not connect to its privileged Closed-Lid helper."
        case .helper(let message): message
        }
    }
}
