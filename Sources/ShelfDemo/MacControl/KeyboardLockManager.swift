import AppKit
import Combine
import CoreGraphics
import Foundation

enum KeyboardLockState: Equatable {
    case idle
    case countingDown(Int)
    case locked
    case permissionRequired
    case unavailable
}

@MainActor
protocol KeyboardLockMonitoring: AnyObject {
    var hasListenPermission: Bool { get }
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
        guard monitor.hasListenPermission else {
            state = .permissionRequired
            return
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
        guard monitor.start(onUnlock: { [weak self] in
            self?.unlockFromFailSafe()
        }) else {
            state = .unavailable
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

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
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
    var hasListenPermission: Bool { CGPreflightListenEventAccess() }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var context: KeyboardTapContext?

    func start(onUnlock: @escaping @MainActor @Sendable () -> Void) -> Bool {
        stop()
        guard hasListenPermission else { return false }

        let context = KeyboardTapContext(onUnlock: onUnlock)
        context.filter.lockKeyboard()
        let eventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
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
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        context = nil
    }

    isolated deinit {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
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
