// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

/// Only absolute pointer travel counts; changing shell geometry cannot create a stroke.
struct CatEdgeRub {
    private struct Stroke {
        let side: CatSide
        let zone: CGRect
        var began: TimeInterval?
        var extreme: CGPoint
        var horizontal = true
        var direction = 0
        var reversals = 0
    }
    private var stroke: Stroke?
    private var nextAllowed: TimeInterval = 0
    static func zone(_ side: CatSide, frame: CGRect) -> CGRect {
        CGRect(x: side == .left ? frame.minX - 32 : frame.maxX - 24,
               y: frame.minY - 10, width: 56, height: frame.height + 20)
    }
    static func side(at point: CGPoint, frame: CGRect) -> CatSide? {
        guard frame.width > 0, frame.height >= 24 else { return nil }
        return CatSide.allCases.first { zone($0, frame: frame).contains(point) }
    }
    mutating func reset() { stroke = nil }
    mutating func consume(point: CGPoint, frame: CGRect, at time: TimeInterval) -> CatSide? {
        guard time >= nextAllowed else { return nil }
        if let current = stroke {
            let expired = current.began.map { time - $0 > 1.6 || time < $0 } ?? false
            if expired || !current.zone.contains(point) { stroke = nil }
        }
        guard var current = stroke else {
            if let side = Self.side(at: point, frame: frame) {
                stroke = Stroke(side: side, zone: Self.zone(side, frame: frame), extreme: point)
            }
            return nil
        }
        let dx = point.x - current.extreme.x, dy = point.y - current.extreme.y
        if current.direction == 0 {
            if max(abs(dx), abs(dy)) >= 6 {
                current.horizontal = abs(dx) >= abs(dy)
                current.direction = (current.horizontal ? dx : dy) > 0 ? 1 : -1
                current.extreme = point; current.began = time
            }
        } else {
            let delta = current.horizontal ? dx : dy
            if delta * CGFloat(current.direction) > 0 { current.extreme = point }
            else if abs(delta) >= 6 {
                current.direction *= -1; current.extreme = point; current.reversals += 1
            }
        }
        stroke = current
        guard current.reversals >= 2 else { return nil }
        stroke = nil; nextAllowed = time + 3
        return current.side
    }
}
