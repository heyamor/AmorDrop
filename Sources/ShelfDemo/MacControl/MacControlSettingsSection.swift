import AppKit
import SwiftUI

private enum MacControlAlert: String, Identifiable {
    case permission
    case unavailable
    case keepAwakeFailure
    case closedLid
    case closedLidFailure
    case removeHelper

    var id: String { rawValue }
}

struct MacControlSettingsSection: View {
    @ObservedObject var coordinator: MacControlCoordinator
    @ObservedObject var keepAwake: KeepAwakeSessionManager
    @ObservedObject var closedLid: ClosedLidManager
    @ObservedObject private var keyboardLock: KeyboardLockManager
    @ObservedObject private var statistics: SessionStatistics

    init(coordinator: MacControlCoordinator, keepAwake: KeepAwakeSessionManager, closedLid: ClosedLidManager) {
        self.coordinator = coordinator
        self.keepAwake = keepAwake
        self.closedLid = closedLid
        self.keyboardLock = coordinator.keyboardLock
        self.statistics = coordinator.statistics
    }

    @State private var durationMinutes = 60
    @State private var customHours = 1
    @State private var customMinutes = 0
    @State private var confirmClearStatistics = false
    @State private var allowDisplaySleep = true
    @State private var lowBatteryProtection = true
    @State private var lowBatteryThreshold = 20
    @State private var powerAdapterTrigger = false
    @State private var selectedAppBundleIdentifiers = Set<String>()
    @State private var closedLidDurationMinutes = -1
    @State private var closedLidCustomHours = 2
    @State private var runningApps: [RunningAppChoice] = []
    @State private var alert: MacControlAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Mac Control"))
                .font(.system(size: 13, weight: .semibold))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwakeStatus)
                        .font(.system(size: 12, weight: .medium))
                    Text(L("macControl.awake.description"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(keepAwake.session(for: .manual) == nil
                       ? L("Start") : L("End Session")) {
                    if keepAwake.session(for: .manual) == nil {
                        if !coordinator.startManualKeepAwake(duration: selectedDuration) {
                            alert = .keepAwakeFailure
                        }
                    } else {
                        coordinator.endManualKeepAwake()
                    }
                }
                .controlSize(.small)
                .disabled(keepAwake.session(for: .manual) == nil && durationMinutes == 0 && customHours == 0 && customMinutes == 0)
            }

            Picker(L("Duration"), selection: $durationMinutes) {
                ForEach(SessionDurationOptions.minutes, id: \.self) { value in
                    Text(SessionDurationOptions.label(minutes: value)).tag(value)
                }
                Text(L("Custom Duration…")).tag(0)
                Text(L("Indefinitely")).tag(-1)
            }
            if durationMinutes == 0 {
                HStack {
                    Stepper("\(customHours) \(L("hours"))", value: $customHours, in: 0...48)
                    Stepper("\(customMinutes) \(L("minutes"))", value: $customMinutes, in: 0...59)
                }
                if customHours == 0 && customMinutes == 0 {
                    Text(L("Choose a duration greater than zero")).foregroundStyle(.secondary)
                }
            }

            Group {
                Toggle(L("Allow display to sleep"), isOn: binding(
                    value: allowDisplaySleep,
                    key: MacControlPreference.allowDisplaySleep
                ) { allowDisplaySleep = $0 })
                .toggleStyle(.switch)

                if let battery = coordinator.battery {
                    Text(batteryStatus(battery))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(L("Stop Keep Awake below"), isOn: binding(
                value: lowBatteryProtection,
                key: MacControlPreference.lowBatteryProtection
            ) { lowBatteryProtection = $0 })
            .toggleStyle(.switch)

            if lowBatteryProtection {
                Picker(L("Battery threshold"), selection: binding(
                    value: lowBatteryThreshold,
                    key: MacControlPreference.lowBatteryThreshold
                ) { lowBatteryThreshold = $0 }) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()

            Toggle(L("Keep awake when connected to power"), isOn: binding(
                value: powerAdapterTrigger,
                key: MacControlPreference.powerAdapterTrigger
            ) { powerAdapterTrigger = $0 })
            .toggleStyle(.switch)

            HStack {
                Text(L("Keep awake while these apps run"))
                Spacer(minLength: 4)
                Button(L("Refresh")) { refreshRunningApps() }
                    .controlSize(.small)
            }

            if runningApps.isEmpty {
                Text(L("macControl.apps.none"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(runningApps) { app in
                        Toggle(app.name, isOn: Binding(
                            get: { selectedAppBundleIdentifiers.contains(app.bundleIdentifier) },
                            set: { setAppTrigger(app.bundleIdentifier, enabled: $0) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 4)
            }

            Text(L("macControl.apps.description"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            statisticsSection
            Divider()

            Text(L("Closed-Lid Mode"))
                .font(.system(size: 12, weight: .medium))
            Picker(L("Duration"), selection: $closedLidDurationMinutes) {
                ForEach(SessionDurationOptions.minutes, id: \.self) { value in
                    Text(SessionDurationOptions.label(minutes: value)).tag(value)
                }
                Text(L("Custom Duration…")).tag(0)
                Text(L("Indefinitely")).tag(-1)
            }
            .disabled(closedLid.sessionActive)
            if closedLidDurationMinutes == 0 {
                Stepper("\(closedLidCustomHours) \(L("hours"))", value: $closedLidCustomHours, in: 1...48)
                    .disabled(closedLid.sessionActive)
            }
            Toggle(L("Allow Mac to keep running with lid closed"), isOn: Binding(
                get: { closedLid.sessionActive },
                set: { enabled in
                    guard closedLid.isAuthorized else {
                        alert = .closedLid
                        return
                    }
                    Task { @MainActor in
                        do {
                            if enabled {
                                try await closedLid.startSession(
                                    lowBatteryProtectionEnabled: lowBatteryProtection,
                                    threshold: lowBatteryThreshold,
                                    durationSeconds: selectedClosedLidDurationSeconds
                                )
                            } else {
                                try await closedLid.stopSession()
                            }
                        } catch {
                            alert = .closedLidFailure
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .disabled(!closedLid.isAuthorized)
            Text(closedLidStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("macControl.closedLid.timerNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L("Lock the user session when the lid closes"), isOn: .constant(true))
                .toggleStyle(.switch)
                .disabled(true)
            Text(L("macControl.closedLid.lockDefault"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if closedLid.isAuthorized {
                    Button(L("Open Login Items Settings")) {
                        closedLid.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                    Button(L("Remove Helper…")) { alert = .removeHelper }
                        .controlSize(.small)
                } else {
                    Button(L("Set up Closed-Lid Mode…")) { alert = .closedLid }
                        .controlSize(.small)
                    Button(L("Refresh Status")) { closedLid.refreshStatus() }
                        .controlSize(.small)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Keyboard Cleaning Lock"))
                        .font(.system(size: 12, weight: .medium))
                    Text(L("macControl.keyboard.shortcut"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(keyboardButtonTitle) {
                    if coordinator.keyboardLock.state == .locked {
                        coordinator.keyboardLock.unlock()
                    } else {
                        coordinator.requestKeyboardLock()
                        if coordinator.keyboardLock.state == .permissionRequired {
                            alert = .permission
                        } else if coordinator.keyboardLock.state == .unavailable {
                            alert = .unavailable
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear {
            loadPreferences()
            closedLid.refreshStatus()
        }
        .onChange(of: closedLidDurationMinutes) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: MacControlPreference.closedLidDurationMinutes)
        }
        .onChange(of: closedLidCustomHours) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: MacControlPreference.closedLidCustomHours)
        }
        .onChange(of: coordinator.keyboardLock.state) { _, newState in
            if newState == .unavailable { alert = .unavailable }
            if newState == .permissionRequired { alert = .permission }
        }
        .alert(item: $alert) { value in
            switch value {
            case .permission:
                return Alert(
                    title: Text(L("Keyboard Lock Permission Required")),
                    message: Text(L(coordinator.keyboardLock.permissionGuideKey)),
                    primaryButton: .default(Text(L(coordinator.keyboardLock.permissionSettingsTitleKey))) {
                        coordinator.keyboardLock.openKeyboardPermissionSettings()
                        coordinator.keyboardLock.returnToIdle()
                    },
                    secondaryButton: .cancel(Text(L("Cancel"))) {
                        coordinator.keyboardLock.returnToIdle()
                    }
                )
            case .unavailable:
                return Alert(
                    title: Text(L("Keyboard Lock Unavailable")),
                    message: Text(L("macControl.keyboard.unavailable")),
                    dismissButton: .default(Text(L("OK"))) {
                        coordinator.keyboardLock.returnToIdle()
                    }
                )
            case .keepAwakeFailure:
                let message = coordinator.keepAwakeBlockedByLowBattery
                    ? L("macControl.keepAwake.lowBatteryBlocked")
                    : L("macControl.keepAwake.assertionFailed")
                return Alert(
                    title: Text(L("Couldn't Start Keep Awake")),
                    message: Text(message),
                    dismissButton: .default(Text(L("OK")))
                )
            case .closedLid:
                let actionTitle = closedLid.registrationStatus == .requiresApproval
                    ? L("Open Login Items Settings") : L("Request Helper Approval")
                return Alert(
                    title: Text(L("Closed-Lid Mode Needs Setup")),
                    message: Text(L("macControl.closedLid.setupRequired")),
                    primaryButton: .default(Text(actionTitle)) {
                        do { try closedLid.requestHelperAuthorization() }
                        catch { alert = .closedLidFailure }
                    },
                    secondaryButton: .cancel(Text(L("Cancel")))
                )
            case .closedLidFailure:
                return Alert(
                    title: Text(L("Closed-Lid Mode Error")),
                    message: Text(closedLid.lastError ?? L("macControl.closedLid.helperFailure")),
                    dismissButton: .default(Text(L("OK")))
                )
            case .removeHelper:
                return Alert(
                    title: Text(L("Remove AmorDrop Helper?")),
                    message: Text(L("macControl.closedLid.removeWarning")),
                    primaryButton: .destructive(Text(L("Remove Helper"))) {
                        Task { @MainActor in
                            do { try await closedLid.unregisterHelper() }
                            catch { alert = .closedLidFailure }
                        }
                    },
                    secondaryButton: .cancel(Text(L("Cancel")))
                )
            }
        }
    }

    private var keepAwakeStatus: String {
        guard let session = keepAwake.session(for: .manual) else {
            return keepAwake.isActive
                ? "\(L("Keep Mac Awake")) · \(L("On"))"
                : L("Keep Mac Awake")
        }
        guard let deadline = session.deadline else {
            return "\(L("Keep Mac Awake")) · \(L("Indefinitely"))"
        }
        return "\(L("Keep Mac Awake")) · \(SessionDurationOptions.clock(deadline.timeIntervalSince(keepAwake.currentTime)))"
    }

    private var selectedDuration: KeepAwakeDuration {
        if durationMinutes == -1 { return .indefinite }
        return .minutes(durationMinutes == 0 ? customHours * 60 + customMinutes : durationMinutes)
    }

    private var selectedClosedLidDurationSeconds: Int64 {
        if closedLidDurationMinutes == -1 { return 0 }
        if closedLidDurationMinutes == 0 { return Int64(closedLidCustomHours * 60 * 60) }
        return Int64(closedLidDurationMinutes * 60)
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Session Statistics")).font(.system(size: 12, weight: .medium))
            Toggle(L("Record sessions on this Mac"), isOn: $statistics.enabled).toggleStyle(.switch)
            HStack {
                Text("\(L("Completed sessions")): \(statistics.count)")
                Spacer()
                Text("\(L("Total session time")): \(SessionDurationOptions.clock(statistics.seconds))")
            }
            Text(L("macControl.statistics.scope"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(L("Recent Sessions")) {
                ForEach(statistics.records.prefix(10)) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(L(record.source))
                            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(SessionDurationOptions.clock(record.duration)).monospacedDigit()
                    }.font(.system(size: 11))
                }
                if statistics.records.isEmpty { Text(L("No completed sessions yet")) }
            }
            Button(L("Clear Session Statistics…")) { confirmClearStatistics = true }
                .disabled(statistics.count == 0)
                .confirmationDialog(L("Clear Session Statistics?"), isPresented: $confirmClearStatistics) {
                    Button(L("Clear"), role: .destructive) { statistics.clear() }
                    Button(L("Cancel"), role: .cancel) {}
                }
        }
    }

    private var closedLidStatus: String {
        if closedLid.sessionActive {
            let active = L("macControl.closedLid.active")
            guard let endsAt = closedLid.sessionEndsAt else { return active }
            return "\(active) · \(SessionDurationOptions.clock(endsAt.timeIntervalSince(closedLid.currentTime)))"
        }
        switch closedLid.registrationStatus {
        case .enabled:
            return L("macControl.closedLid.ready")
        case .requiresApproval:
            return L("macControl.closedLid.approvalRequired")
        case .notFound:
            return L("macControl.closedLid.helperMissing")
        case .notRegistered:
            return L("macControl.closedLid.unavailable")
        @unknown default:
            return L("macControl.closedLid.unavailable")
        }
    }

    private var keyboardButtonTitle: String {
        switch coordinator.keyboardLock.state {
        case .countingDown(let seconds): return "\(L("Lock Keyboard")) · \(seconds)"
        case .locked: return L("Unlock Keyboard")
        case .permissionRequired: return L("Permission Required")
        case .unavailable: return L("Unavailable")
        case .idle: return L("Lock Keyboard")
        }
    }

    private func binding<Value: Equatable>(
        value: Value,
        key: String,
        update: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { value },
            set: { newValue in
                guard newValue != value else { return }
                update(newValue)
                UserDefaults.standard.set(newValue, forKey: key)
                MacControlPreference.publishChanges()
            }
        )
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        allowDisplaySleep = defaults.object(forKey: MacControlPreference.allowDisplaySleep) as? Bool ?? true
        lowBatteryProtection = defaults.object(forKey: MacControlPreference.lowBatteryProtection) as? Bool ?? true
        lowBatteryThreshold = defaults.object(forKey: MacControlPreference.lowBatteryThreshold) as? Int ?? 20
        closedLidDurationMinutes = defaults.object(forKey: MacControlPreference.closedLidDurationMinutes) as? Int ?? -1
        closedLidCustomHours = min(48, max(1, defaults.object(forKey: MacControlPreference.closedLidCustomHours) as? Int ?? 2))
        powerAdapterTrigger = defaults.bool(forKey: MacControlPreference.powerAdapterTrigger)
        selectedAppBundleIdentifiers = Set(
            defaults.stringArray(forKey: MacControlPreference.selectedAppBundleIdentifiers) ?? []
        )
        refreshRunningApps()
    }

    private func refreshRunningApps() {
        let currentlyRunning = coordinator.runningApplications()
        let runningIDs = Set(currentlyRunning.map(\.bundleIdentifier))
        let selectedButStopped = selectedAppBundleIdentifiers.subtracting(runningIDs).map { bundleID in
            let resolvedName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .flatMap(Bundle.init(url:))
                .flatMap { $0.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
                ?? bundleID
            return RunningAppChoice(
                bundleIdentifier: bundleID,
                name: "\(resolvedName)\(L(" (not running)"))"
            )
        }
        runningApps = (currentlyRunning + selectedButStopped)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func setAppTrigger(_ bundleIdentifier: String, enabled: Bool) {
        if enabled {
            selectedAppBundleIdentifiers.insert(bundleIdentifier)
        } else {
            selectedAppBundleIdentifiers.remove(bundleIdentifier)
        }
        UserDefaults.standard.set(
            selectedAppBundleIdentifiers.sorted(),
            forKey: MacControlPreference.selectedAppBundleIdentifiers
        )
        MacControlPreference.publishChanges()
    }

    private func batteryStatus(_ battery: BatterySnapshot) -> String {
        if battery.externalPowerConnected { return L("Connected to power") }
        if let percent = battery.percent { return "\(L("On battery")) · \(percent)%" }
        return L("Battery status unavailable")
    }
}

struct KeyboardLockOverlay: View {
    @ObservedObject var manager: KeyboardLockManager

    var body: some View {
        VStack(spacing: 12) {
            switch manager.state {
            case .countingDown(let seconds):
                Text("\(seconds)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                Text(L("Keyboard lock starting"))
                    .font(.system(size: 13))
            case .locked:
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 24))
                Text(L("Keyboard Locked"))
                    .font(.system(size: 15, weight: .semibold))
                Button(L("Unlock Keyboard")) { manager.unlock() }
                    .keyboardShortcut(.defaultAction)
            default:
                EmptyView()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.25)))
    }
}
