import ClosedLidCore
import Foundation
import IOKit.ps

private let serviceName = "com.amor.personal.amordrop.closed-lid"

private final class PMSetSleepSettingController: SleepSettingControlling {
    func readSleepDisabled() throws -> Bool {
        let output = try run(arguments: ["-g"])
        guard let match = output.range(of: #"(?m)^\s*SleepDisabled\s+([01])\s*$"#, options: .regularExpression),
              let value = output[match].last,
              value == "0" || value == "1" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value == "1"
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        _ = try run(arguments: ["-a", "disablesleep", disabled ? "1" : "0"])
    }

    private func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: err, encoding: .utf8) ?? "pmset failed"
            throw NSError(
                domain: "AmorDropClosedLidHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return String(data: out, encoding: .utf8) ?? ""
    }
}

private final class HelperEndpoint: NSObject, ClosedLidHelperXPCProtocol {
    private let controller: ClosedLidSessionController
    private let store: ClosedLidStateStoring
    private let stateQueue = DispatchQueue(label: "com.amor.personal.amordrop.closed-lid.state")
    private var clientConnection: NSXPCConnection?
    private var recoveryError: Error?
    private var batteryTimer: DispatchSourceTimer?

    init(controller: ClosedLidSessionController, store: ClosedLidStateStoring) {
        self.controller = controller
        self.store = store
        super.init()
        do {
            try controller.recoverStaleSession()
            NSLog("AmorDrop Closed-Lid helper: recovered any stale power state")
        } catch {
            recoveryError = error
            NSLog("AmorDrop Closed-Lid helper: recovery failed: %@", error.localizedDescription)
        }
    }

    func accept(_ connection: NSXPCConnection) -> Bool {
        stateQueue.sync {
            guard clientConnection == nil, recoveryError == nil else { return false }
            clientConnection = connection
            connection.invalidationHandler = { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.stateQueue.async {
                    guard self.clientConnection === connection else { return }
                    self.clientConnection = nil
                    self.stopBatteryMonitor()
                    do {
                        try self.controller.stopAndRestore()
                        NSLog("AmorDrop Closed-Lid helper: session ended after app disconnected")
                    } catch {
                        NSLog("AmorDrop Closed-Lid helper: disconnect recovery failed: %@", error.localizedDescription)
                    }
                }
            }
            connection.interruptionHandler = { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.stateQueue.async {
                    guard self.clientConnection === connection else { return }
                    do {
                        try self.controller.stopAndRestore()
                    } catch {
                        NSLog("AmorDrop Closed-Lid helper: interruption recovery failed: %@", error.localizedDescription)
                    }
                }
            }
            return true
        }
    }

    func startSession(
        lowBatteryProtectionEnabled: Bool,
        lowBatteryThreshold: Int,
        reply: @escaping (Bool, String?) -> Void
    ) {
        stateQueue.async {
            guard self.recoveryError == nil else {
                reply(false, self.recoveryError?.localizedDescription ?? "Recovery is required")
                return
            }
            do {
                _ = try self.controller.start(
                    lowBatteryProtectionEnabled: lowBatteryProtectionEnabled,
                    lowBatteryThreshold: lowBatteryThreshold
                )
                self.startBatteryMonitor()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func stopSession(reply: @escaping (Bool, String?) -> Void) {
        stateQueue.async {
            do {
                try self.controller.stopAndRestore()
                self.stopBatteryMonitor()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func getSessionStatus(reply: @escaping (Bool, String?) -> Void) {
        stateQueue.async {
            do {
                reply(try self.store.load() != nil, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    private func startBatteryMonitor() {
        guard batteryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 10, repeating: 30)
        timer.setEventHandler { [weak self] in self?.checkBattery() }
        batteryTimer = timer
        timer.resume()
        checkBattery()
    }

    private func stopBatteryMonitor() {
        batteryTimer?.cancel()
        batteryTimer = nil
    }

    private func checkBattery() {
        let battery = readBattery()
        do {
            if try controller.endForLowBatteryIfNeeded(
                isOnBattery: battery?.isOnBattery,
                percent: battery?.percent
            ) {
                NSLog("AmorDrop Closed-Lid helper: session ended at low battery")
                stopBatteryMonitor()
            }
        } catch {
            NSLog("AmorDrop Closed-Lid helper: low-battery recovery failed: %@", error.localizedDescription)
        }
    }

    private func readBattery() -> (isOnBattery: Bool, percent: Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType as String,
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0,
                  let sourceState = description[kIOPSPowerSourceStateKey as String] as? String else {
                continue
            }
            return (sourceState == "Battery Power", min(100, current * 100 / maximum))
        }
        return nil
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let endpoint: HelperEndpoint

    init(endpoint: HelperEndpoint) { self.endpoint = endpoint }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard endpoint.accept(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: ClosedLidHelperXPCProtocol.self)
        connection.exportedObject = endpoint
        connection.resume()
        return true
    }
}

private let store = PropertyListClosedLidStateStore()
private let controller = ClosedLidSessionController(settings: PMSetSleepSettingController(), store: store)
private let endpoint = HelperEndpoint(controller: controller, store: store)
private let listener = NSXPCListener(machServiceName: serviceName)
private let delegate = ListenerDelegate(endpoint: endpoint)
listener.delegate = delegate
listener.resume()
dispatchMain()
