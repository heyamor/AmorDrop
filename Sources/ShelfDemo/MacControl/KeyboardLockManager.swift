import AppKit
import Combine
import CoreGraphics
import Foundation
import ApplicationServices
import IOKit.hid

enum KeyboardLockState: Equatable {
    case idle
    case countingDown(Int)
    case locked
    case permissionRequired
    case unavailable
}

@MainActor
protocol KeyboardLockMonitoring: AnyObject {
    var hasAccessibilityPermission: Bool { get }
    var hasInputMonitoringPermission: Bool { get }
    func requestAccessibilityPermission() -> Bool
    func start(onUnlock: @escaping @MainActor @Sendable () -> Void) -> Bool
    func stop()
}

@MainActor
final class KeyboardLockManager: ObservableObject {
    @Published private(set) var state: KeyboardLockState = .idle

    private let monitor: KeyboardLockMonitoring
    private var countdownTimer: Timer?

    init(monitor: KeyboardLockMonitoring? = nil) {
        self.monitor = monitor ?? CGKeyboardLockMonitor()
    }

    func beginLockRequest() {
        guard state == .idle else { return }
        if !monitor.hasAccessibilityPermission {
            guard monitor.requestAccessibilityPermission(), monitor.hasAccessibilityPermission else {
                state = .permissionRequired
                return
            }
        }
        state = .countingDown(3)
        scheduleCountdown()
    }

    /// One tick per second; internal visibility permits deterministic tests.
    func advanceCountdown() {
        guard case .countingDown(let seconds) = state else { return }
        if seconds > 1 {
            state = .countingDown(seconds - 1)
            scheduleCountdown()
            return
        }

        countdownTimer?.invalidate()
        countdownTimer = nil
        guard monitor.hasAccessibilityPermission else {
            state = .permissionRequired
            return
        }
        guard monitor.start(onUnlock: { [weak self] in
            self?.unlockFromFailSafe()
        }) else {
            monitor.stop()
            state = monitor.hasAccessibilityPermission && monitor.hasInputMonitoringPermission ? .unavailable : .permissionRequired
            return
        }
        state = .locked
    }

    func unlock() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        monitor.stop()
        state = .idle
    }

    private var needsInputMonitoring: Bool {
        monitor.hasAccessibilityPermission && !monitor.hasInputMonitoringPermission
    }

    var permissionGuideKey: String {
        needsInputMonitoring ? "macControl.keyboard.inputPermissionGuide" : "macControl.keyboard.permissionGuide"
    }

    var permissionSettingsTitleKey: String {
        needsInputMonitoring ? "Open Input Monitoring Settings" : "Open Accessibility Settings"
    }

    func openKeyboardPermissionSettings() {
        let pane: String
        if needsInputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            pane = "Privacy_ListenEvent"
        } else {
            pane = "Privacy_Accessibility"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func returnToIdle() {
        guard state == .permissionRequired || state == .unavailable else { return }
        state = .idle
    }

    func shutdown() {
        unlock()
    }

    private func scheduleCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceCountdown() }
        }
    }

    private func unlockFromFailSafe() {
        // A disabled/timed-out Quartz tap has already stopped filtering input.
        // Remove our overlay and mark the lock off rather than trying to
        // resurrect a tap that macOS has disabled.
        countdownTimer?.invalidate()
        countdownTimer = nil
        monitor.stop()
        state = .idle
    }

    isolated deinit {
        countdownTimer?.invalidate()
        monitor.stop()
    }
}

private final class KeyboardTapContext: @unchecked Sendable {
    let filter = KeyboardLockEventFilter()
    let onUnlock: @MainActor @Sendable () -> Void

    init(onUnlock: @escaping @MainActor @Sendable () -> Void) {
        self.onUnlock = onUnlock
    }
}

@MainActor
final class CGKeyboardLockMonitor: KeyboardLockMonitoring {
    // A defaultTap suppresses events and requires Accessibility authorization.
    // Input Monitoring only authorizes passive listenOnly taps.
    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }
    var hasInputMonitoringPermission: Bool { CGPreflightListenEventAccess() }

    static let requiredKeyboardMask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

    /// Quartz may silently strip unauthorized key events while retaining
    /// flagsChanged. An enabled port alone is not proof of a keyboard lock.
    static func isCompleteKeyboardTap(_ info: CGEventTapInformation, processID: pid_t) -> Bool {
        info.tappingProcess == processID && info.enabled
            && info.options == .defaultTap && info.tapPoint == .cgSessionEventTap
            && info.eventsOfInterest & requiredKeyboardMask == requiredKeyboardMask
    }

    private static func hasCompleteKeyboardTap() -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return false }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        let capacity = count
        guard CGGetEventTapList(capacity, &taps, &count) == .success else { return false }
        return taps.prefix(Int(min(count, capacity))).contains {
            isCompleteKeyboardTap($0, processID: getpid())
        }
    }

    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func permissionDiagnostic() -> String {
        let authorized = AXIsProcessTrusted()
        var canCreateFilteringTap = false
        if authorized, let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil
        ) {
            canCreateFilteringTap = CGEvent.tapIsEnabled(tap: tap)
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        return "bundle=\(Bundle.main.bundlePath) accessibility=\(authorized) inputMonitoring=\(CGPreflightListenEventAccess()) filteringTap=\(canCreateFilteringTap)"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var context: KeyboardTapContext?
    private var healthTimer: Timer?

    func start(onUnlock: @escaping @MainActor @Sendable () -> Void) -> Bool {
        stop()
        guard hasAccessibilityPermission else { return false }

        let context = KeyboardTapContext(onUnlock: onUnlock)
        context.filter.lockKeyboard()
        let eventMask = Self.requiredKeyboardMask
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.receiveEvent,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        self.context = context
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap), Self.hasCompleteKeyboardTap() else {
            NSLog("AmorDrop keyboard lock: incomplete event tap; accessibility=%d inputMonitoring=%d",
                  hasAccessibilityPermission, hasInputMonitoringPermission)
            stop()
            return false
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let tap = self.eventTap else { return }
                guard CGEvent.tapIsEnabled(tap: tap), Self.hasCompleteKeyboardTap() else {
                    let notify = self.context?.onUnlock
                    self.stop()
                    notify?()
                    return
                }
            }
        }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        context = nil
    }

    isolated deinit {
        healthTimer?.invalidate()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private static let receiveEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<KeyboardTapContext>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            _ = context.filter.handle(KeyboardLockInput(
                kind: .tapDisabled,
                keyCode: 0,
                timestamp: 0,
                unlockModifiersAreDown: false
            ))
            Task { @MainActor in context.onUnlock() }
            return Unmanaged.passUnretained(event)
        }

        let kind: KeyboardLockEventKind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return Unmanaged.passUnretained(event)
        }

        let requiredModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        let modifiersAreDown = event.flags.intersection(requiredModifiers) == requiredModifiers
        let disposition = context.filter.handle(KeyboardLockInput(
            kind: kind,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            timestamp: TimeInterval(event.timestamp) / 1_000_000_000,
            unlockModifiersAreDown: modifiersAreDown
        ))
        if disposition == .unlocked {
            Task { @MainActor in context.onUnlock() }
        }
        return disposition == .passThrough ? Unmanaged.passUnretained(event) : nil
    }
}
