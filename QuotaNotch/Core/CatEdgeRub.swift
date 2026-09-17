// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

/// Screen coordinates deliberately separate pointer travel from moving layout geometry.
struct CatEdgeRub {
    private struct Stroke {
        let side: CatSide
        let zone: CGRect
        let began: TimeInterval
        var extreme: CGFloat
        var direction = 0
        var reversals = 0
    }
    private var stroke: Stroke?
    private var nextAllowed: TimeInterval = 0
    static func zone(_ side: CatSide, frame: CGRect) -> CGRect {
        CGRect(x: side == .left ? frame.minX - 20 : frame.maxX - 10,
               y: frame.minY - 6, width: 30, height: frame.height + 12)
    }
    static func side(at point: CGPoint, frame: CGRect) -> CatSide? {
        guard frame.width > 0, frame.height >= 24 else { return nil }
        return CatSide.allCases.first { zone($0, frame: frame).contains(point) }
    }
    mutating func reset() { stroke = nil }
    mutating func consume(point: CGPoint, frame: CGRect, at time: TimeInterval) -> CatSide? {
        guard time >= nextAllowed else { return nil }
        if let current = stroke,
           time - current.began > 1.15 || time < current.began || !current.zone.contains(point) {
            stroke = nil
        }
        guard var current = stroke else {
            if let side = Self.side(at: point, frame: frame) {
                stroke = Stroke(side: side, zone: Self.zone(side, frame: frame), began: time, extreme: point.x)
            }
            return nil
        }
        let delta = point.x - current.extreme
        if current.direction == 0 {
            if abs(delta) >= 10 { current.direction = delta > 0 ? 1 : -1; current.extreme = point.x }
        } else if delta * CGFloat(current.direction) > 0 {
            current.extreme = point.x
        } else if abs(delta) >= 10 {
            current.direction *= -1; current.extreme = point.x; current.reversals += 1
        }
        stroke = current
        guard current.reversals >= 2 else { return nil }
        stroke = nil; nextAllowed = time + 3
        return current.side
    }
}
