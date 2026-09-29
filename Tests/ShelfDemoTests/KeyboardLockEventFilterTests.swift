import XCTest
import CoreGraphics
@testable import AmorDrop

final class KeyboardLockEventFilterTests: XCTestCase {
    private func input(
        _ kind: KeyboardLockEventKind,
        keyCode: UInt16 = 0,
        time: TimeInterval = 0,
        chord: Bool = false
    ) -> KeyboardLockInput {
        KeyboardLockInput(kind: kind, keyCode: keyCode, timestamp: time, unlockModifiersAreDown: chord)
    }

    func test_unlocked_filter_passes_all_keys() {
        let filter = KeyboardLockEventFilter()
        XCTAssertEqual(filter.handle(input(.keyDown, keyCode: 0)), .passThrough)
    }

    func test_lock_swallows_regular_key_down_key_up_and_modifier_events() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()
        XCTAssertEqual(filter.handle(input(.keyDown, keyCode: 0)), .swallow)
        XCTAssertEqual(filter.handle(input(.keyUp, keyCode: 0)), .swallow)
        XCTAssertEqual(filter.handle(input(.flagsChanged)), .swallow)
    }

    func test_unlock_chord_requires_full_two_second_hold() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()
        XCTAssertEqual(filter.handle(input(.keyDown, keyCode: 37, time: 1, chord: true)), .swallow)
        XCTAssertEqual(filter.handle(input(.keyUp, keyCode: 37, time: 2.99, chord: true)), .swallow)
        XCTAssertTrue(filter.isLocked)
    }

    func test_unlock_chord_unlocks_at_two_seconds_and_is_consumed() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()
        XCTAssertEqual(filter.handle(input(.keyDown, keyCode: 37, time: 1, chord: true)), .swallow)
        XCTAssertEqual(filter.handle(input(.keyUp, keyCode: 37, time: 3, chord: true)), .unlocked)
        XCTAssertFalse(filter.isLocked)
        XCTAssertEqual(filter.handle(input(.keyDown, keyCode: 0, time: 4)), .passThrough)
    }

    func test_releasing_a_required_modifier_cancels_the_unlock_chord() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()
        _ = filter.handle(input(.keyDown, keyCode: 37, time: 1, chord: true))
        _ = filter.handle(input(.flagsChanged, time: 2, chord: false))

        XCTAssertEqual(filter.handle(input(.keyUp, keyCode: 37, time: 4, chord: true)), .swallow)
        XCTAssertTrue(filter.isLocked)
    }

    func test_missing_unlock_modifiers_never_starts_unlock() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()
        _ = filter.handle(input(.keyDown, keyCode: 37, time: 1, chord: false))

        XCTAssertEqual(filter.handle(input(.keyUp, keyCode: 37, time: 5, chord: false)), .swallow)
        XCTAssertTrue(filter.isLocked)
    }

    func test_disabled_event_tap_fails_open_and_unlocks() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()

        XCTAssertEqual(filter.handle(input(.tapDisabled)), .passThrough)
        XCTAssertFalse(filter.isLocked)
    }

    func test_explicit_mouse_unlock_restores_key_delivery() {
        let filter = KeyboardLockEventFilter()
        filter.lockKeyboard()
        filter.unlockKeyboard()

        XCTAssertEqual(filter.handle(input(.keyDown, keyCode: 0)), .passThrough)
    }
}


@MainActor
final class KeyboardTapValidationTests: XCTestCase {
    private func tap(mask: CGEventMask, enabled: Bool = true, passive: Bool = false, pid: pid_t = 42) -> CGEventTapInformation {
        var info = CGEventTapInformation()
        info.tappingProcess = pid
        info.tapPoint = .cgSessionEventTap
        info.options = passive ? .listenOnly : .defaultTap
        info.enabled = enabled
        info.eventsOfInterest = mask
        return info
    }

    func test_complete_active_keyboard_tap_is_accepted() {
        XCTAssertTrue(CGKeyboardLockMonitor.isCompleteKeyboardTap(tap(mask: CGKeyboardLockMonitor.requiredKeyboardMask), processID: 42))
    }

    func test_enabled_modifier_only_tap_is_not_a_keyboard_lock() {
        XCTAssertFalse(CGKeyboardLockMonitor.isCompleteKeyboardTap(tap(mask: 1 << CGEventType.flagsChanged.rawValue), processID: 42))
    }

    func test_missing_key_up_is_rejected() {
        let mask = CGKeyboardLockMonitor.requiredKeyboardMask & ~(1 << CGEventType.keyUp.rawValue)
        XCTAssertFalse(CGKeyboardLockMonitor.isCompleteKeyboardTap(tap(mask: mask), processID: 42))
    }

    func test_passive_listener_cannot_prove_keyboard_is_locked() {
        XCTAssertFalse(CGKeyboardLockMonitor.isCompleteKeyboardTap(tap(mask: CGKeyboardLockMonitor.requiredKeyboardMask, passive: true), processID: 42))
    }

    func test_disabled_or_other_process_tap_is_rejected() {
        XCTAssertFalse(CGKeyboardLockMonitor.isCompleteKeyboardTap(tap(mask: CGKeyboardLockMonitor.requiredKeyboardMask, enabled: false), processID: 42))
        XCTAssertFalse(CGKeyboardLockMonitor.isCompleteKeyboardTap(tap(mask: CGKeyboardLockMonitor.requiredKeyboardMask, pid: 99), processID: 42))
    }
}
