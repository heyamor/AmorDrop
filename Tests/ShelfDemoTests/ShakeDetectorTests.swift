import XCTest
@testable import AmorDrop

final class ShakeDetectorTests: XCTestCase {
    private func sweep(_ detector: ShakeDetector, start: Double, step: Double = 0.04) -> Int {
        [0.0, 40, 0, 40, 0, 40].enumerated().filter {
            detector.recordDrag(x: $0.element, at: start + Double($0.offset) * step)
        }.count
    }

    func test_fast_horizontal_shake_triggers_once() {
        XCTAssertEqual(sweep(ShakeDetector(), start: 10), 1)
    }

    func test_slow_sweeps_and_straight_drag_do_not_trigger() {
        let detector = ShakeDetector()
        XCTAssertEqual(sweep(detector, start: 10, step: 0.2), 0)
        for i in 0..<20 {
            XCTAssertFalse(detector.recordDrag(x: Double(i * 20), at: 20 + Double(i) * 0.01))
        }
    }

    func test_cooldown_avoids_duplicate_shelves_then_allows_next_shake() {
        let detector = ShakeDetector()
        XCTAssertEqual(sweep(detector, start: 10), 1)
        XCTAssertEqual(sweep(detector, start: 10.25), 0)
        XCTAssertEqual(sweep(detector, start: 12), 1)
    }

    func test_release_clears_partial_gesture() {
        let detector = ShakeDetector()
        for (i, x) in [0.0, 40, 0].enumerated() {
            XCTAssertFalse(detector.recordDrag(x: x, at: 10 + Double(i) * 0.04))
        }
        detector.endDrag()
        for (i, x) in [40.0, 0, 40].enumerated() {
            XCTAssertFalse(detector.recordDrag(x: x, at: 10.12 + Double(i) * 0.04))
        }
    }
}
