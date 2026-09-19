// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import QuotaNotchCore

final class CatEdgeRubTests: XCTestCase {
    let frame = CGRect(x: 100, y: 100, width: 200, height: 32)
    func testTwoDeliberateReversalsSummonEachSide() {
        for side in CatSide.allCases {
            var rub = CatEdgeRub()
            let xs: [CGFloat] = side == .left ? [95, 85, 98, 85] : [305, 315, 302, 315]
            for (index, x) in xs.enumerated() {
                let result = rub.consume(point: CGPoint(x: x, y: 115), frame: frame, at: Double(index) * 0.2)
                XCTAssertEqual(result, index == 3 ? side : nil)
            }
        }
    }
    func testPassingAndTinyJitterDoNotSummon() {
        for xs: [CGFloat] in [[80, 85, 90, 95, 100, 105], [95, 96, 94, 97, 93, 96]] {
            var rub = CatEdgeRub()
            for (index, x) in xs.enumerated() {
                XCTAssertNil(rub.consume(point: CGPoint(x: x, y: 110), frame: frame, at: Double(index) * 0.1))
            }
        }
    }
    func testMovingShellUnderStationaryPointerNeverCounts() {
        var rub = CatEdgeRub()
        for (index, x) in [100, 90, 105, 90, 105, 100].enumerated() {
            XCTAssertNil(rub.consume(point: CGPoint(x: 98, y: 115),
                frame: CGRect(x: x, y: 100, width: 200, height: 32), at: Double(index) * 0.1))
        }
    }
    func testGestureKeepsOriginalEdgeWhileShellResizes() {
        var rub = CatEdgeRub()
        let xs: [CGFloat] = [95, 85, 98, 85]
        for (index, x) in xs.enumerated() {
            let moving = frame.offsetBy(dx: CGFloat(index) * -8, dy: 0)
            let result = rub.consume(point: CGPoint(x: x, y: 115), frame: moving, at: Double(index) * 0.2)
            XCTAssertEqual(result, index == 3 ? .left : nil)
        }
    }
    func testNewGestureUsesNewEdgeAfterTimeout() {
        var rub = CatEdgeRub()
        _ = rub.consume(point: CGPoint(x: 95, y: 115), frame: frame, at: 0)
        let expanded = frame.offsetBy(dx: -50, dy: 0)
        for (index, x) in [CGFloat(45), 35, 48, 35].enumerated() {
            XCTAssertEqual(rub.consume(point: CGPoint(x: x, y: 115), frame: expanded, at: 2 + Double(index) * 0.2), index == 3 ? .left : nil)
        }
    }
    func testPauseExitAndInputCancellationBreakStroke() {
        for cancellation in 0..<3 {
            var rub = CatEdgeRub()
            _ = rub.consume(point: CGPoint(x: 95, y: 115), frame: frame, at: 0)
            _ = rub.consume(point: CGPoint(x: 85, y: 115), frame: frame, at: 0.2)
            if cancellation == 0 { rub.reset() }
            if cancellation == 1 { _ = rub.consume(point: CGPoint(x: 200, y: 115), frame: frame, at: 0.3) }
            let start = cancellation == 2 ? 2.0 : 0.4
            XCTAssertNil(rub.consume(point: CGPoint(x: 98, y: 115), frame: frame, at: start))
            XCTAssertNil(rub.consume(point: CGPoint(x: 85, y: 115), frame: frame, at: start + 0.2))
        }
    }
    func testCooldownCannotBeResetByLeaving() {
        var rub = CatEdgeRub()
        for (index, x) in [CGFloat(95), 85, 98, 85].enumerated() {
            _ = rub.consume(point: CGPoint(x: x, y: 115), frame: frame, at: Double(index) * 0.2)
        }
        rub.reset()
        for (index, x) in [CGFloat(95), 85, 98, 85].enumerated() {
            XCTAssertNil(rub.consume(point: CGPoint(x: x, y: 115), frame: frame, at: 1 + Double(index) * 0.2))
        }
    }
    func testMiddleAndOutsideVerticalBandNeverTrigger() {
        for point in [CGPoint(x: 200, y: 115), CGPoint(x: 95, y: 150)] {
            var rub = CatEdgeRub()
            for (index, dx) in [0, -12, 0, -12].enumerated() {
                XCTAssertNil(rub.consume(point: CGPoint(x: point.x + CGFloat(dx), y: point.y), frame: frame, at: Double(index) * 0.2))
            }
        }
    }
    func testRestingAtEdgeDoesNotConsumeGestureDeadline() {
        var rub = CatEdgeRub()
        _ = rub.consume(point: CGPoint(x: 95, y: 115), frame: frame, at: 0)
        XCTAssertNil(rub.consume(point: CGPoint(x: 95, y: 115), frame: frame, at: 10))
        XCTAssertNil(rub.consume(point: CGPoint(x: 85, y: 115), frame: frame, at: 10.2))
        XCTAssertNil(rub.consume(point: CGPoint(x: 98, y: 115), frame: frame, at: 10.6))
        XCTAssertEqual(rub.consume(point: CGPoint(x: 85, y: 115), frame: frame, at: 11.2), .left)
    }
    func testVerticalRubAndWiderInnerEdgeAreRecognized() {
        var rub = CatEdgeRub()
        for (index, y) in [CGFloat(110), 118, 110, 118].enumerated() {
            XCTAssertEqual(rub.consume(point: CGPoint(x: 118, y: y), frame: frame, at: Double(index) * 0.25), index == 3 ? .left : nil)
        }
    }

}
