import Foundation

enum KeyboardLockEventKind {
    case keyDown
    case keyUp
    case flagsChanged
    case tapDisabled
}

struct KeyboardLockInput {
    let kind: KeyboardLockEventKind
    let keyCode: UInt16
    let timestamp: TimeInterval
    let unlockModifiersAreDown: Bool
}

enum KeyboardLockDisposition: Equatable {
    case passThrough
    case swallow
    case unlocked
}

/// Thread-safe event policy shared by the Quartz callback and deterministic tests.
/// It never reads key characters or retains typed content.
final class KeyboardLockEventFilter: @unchecked Sendable {
    static let unlockKeyCode: UInt16 = 37 // ANSI L
    static let requiredHoldDuration: TimeInterval = 2

    private let lock = NSLock()
    private var locked = false
    private var unlockKeyDownAt: TimeInterval?

    var isLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return locked
    }

    func lockKeyboard() {
        lock.lock()
        locked = true
        unlockKeyDownAt = nil
        lock.unlock()
    }

    func unlockKeyboard() {
        lock.lock()
        locked = false
        unlockKeyDownAt = nil
        lock.unlock()
    }

    func handle(_ input: KeyboardLockInput) -> KeyboardLockDisposition {
        lock.lock()
        defer { lock.unlock() }
        guard locked else { return .passThrough }

        if input.kind == .tapDisabled {
            locked = false
            unlockKeyDownAt = nil
            return .passThrough
        }

        switch input.kind {
        case .keyDown where input.keyCode == Self.unlockKeyCode && input.unlockModifiersAreDown:
            if unlockKeyDownAt == nil { unlockKeyDownAt = input.timestamp }
        case .keyUp where input.keyCode == Self.unlockKeyCode:
            if let started = unlockKeyDownAt,
               input.unlockModifiersAreDown,
               input.timestamp - started >= Self.requiredHoldDuration {
                locked = false
                unlockKeyDownAt = nil
                return .unlocked
            }
            unlockKeyDownAt = nil
        case .flagsChanged where !input.unlockModifiersAreDown:
            unlockKeyDownAt = nil
        default:
            break
        }
        return .swallow
    }
}
