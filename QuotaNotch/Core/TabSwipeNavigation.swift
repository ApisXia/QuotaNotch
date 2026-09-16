// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Accumulate small trackpad deltas and emit at most one page change per gesture.
struct TabSwipeNavigation {
    enum Phase { case none, began, changed, ended, cancelled }
    private var horizontal: Double = 0
    private var vertical: Double = 0
    private var previousTime = -Double.infinity
    private var emitted = false
    private var rejected = false
    private(set) var claimed = false

    mutating func reset() { self = Self() }

    mutating func consume(x: Double, y: Double, at time: Double, phase: Phase,
                          precise: Bool = true, momentum: Bool = false) -> Int? {
        guard !momentum else { return nil }
        if phase == .began || (phase == .none && time - previousTime > 0.25) { reset() }
        previousTime = time
        if phase == .cancelled { reset(); return nil }
        if phase == .ended { reset(); return nil }
        guard !emitted, !rejected else { return nil }
        horizontal += x; vertical += abs(y)
        let threshold: Double = precise ? 14 : 2
        if vertical >= threshold && vertical > abs(horizontal) { rejected = true; return nil }
        guard abs(horizontal) >= threshold, abs(horizontal) > vertical * 1.4 else { return nil }
        emitted = true; claimed = true
        return horizontal < 0 ? 1 : -1
    }

    static func destination(current: Int, step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, current + step))
    }
}
