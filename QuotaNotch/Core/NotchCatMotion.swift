// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum CatSide: String, CaseIterable { case left, right }
enum CatAction: String, CaseIterable { case curious, rest, completed, attention }

/// Space belongs to information first. The pet never scales a widget or exceeds its wing budget.
struct CatWingSpace: Equatable {
    let occupied: CGFloat
    let limit: CGFloat
    var room: CGFloat { max(0, limit - occupied) }
    var canPeek: Bool { room >= 16 }
    var isEmpty: Bool { occupied == 0 }
    var excursion: CGFloat { canPeek ? min(room, isEmpty ? 32 : 24) : 0 }
}

struct CatPose: Equatable {
    var side: CatSide = .right
    var action: CatAction = .curious
    var elapsed: Double = 0
    var active = false
    static let duration: Double = 9
    // Paw leads the shell movement; head follows after contact. Return order is reversed.
    var extensionAmount: Double { active ? Self.envelope(elapsed, start: 0.35, rise: 1.1, end: 7.35, fall: 1.45) : 0 }
    var headAmount: Double { active ? Self.envelope(elapsed, start: 0.85, rise: 1.15, end: 6.9, fall: 1.1) : 0 }
    var pawAmount: Double { active ? Self.envelope(elapsed, start: 0, rise: 0.45, end: 8.3, fall: 0.6) : 0 }
    var blink: Bool { (elapsed > 3.15 && elapsed < 3.32) || (elapsed > 5.7 && elapsed < 5.9) }
    static func envelope(_ t: Double, start: Double, rise: Double, end: Double, fall: Double) -> Double {
        func smooth(_ x: Double) -> Double { let x = min(1, max(0, x)); return x * x * (3 - 2 * x) }
        return smooth((t - start) / rise) * (1 - smooth((t - end) / fall))
    }
}

/// Coalesced cues expire instead of replaying after the user closes a panel minutes later.
struct CatCueQueue {
    private(set) var pending: CatAction?
    private var queuedAt: Date = .distantPast
    private var lastShown: Date = .distantPast
    mutating func enqueue(_ action: CatAction, now: Date) {
        guard action == .completed || action == .attention else { return }
        guard now.timeIntervalSince(lastShown) >= 30 else { return }
        if pending != .attention { pending = action }
        queuedAt = now
    }
    mutating func take(now: Date) -> CatAction? {
        defer { pending = nil }
        guard let pending, now.timeIntervalSince(queuedAt) <= 15 else { return nil }
        lastShown = now
        return pending
    }
}
