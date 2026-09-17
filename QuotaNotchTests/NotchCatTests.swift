// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import QuotaNotchCore

final class NotchCatTests: XCTestCase {
    func testWingBudgetsAcrossSizesAndOccupancy() {
        for height: CGFloat in [24, 32, 38] {
            let widget = QuotaCompactMetrics.iconSize(height: height)
            let limit = widget + NotchModuleMetrics(widgetWidth: widget).additionalWidth
            for occupied in [CGFloat(0), widget, limit, limit + 10] {
                let space = CatWingSpace(occupied: occupied, limit: limit)
                XCTAssertLessThanOrEqual(space.excursion, max(0, limit - occupied))
                XCTAssertEqual(space.canPeek, occupied <= widget)
                for tick in 0...900 {
                    let pose = CatPose(elapsed: Double(tick) / 100, active: true)
                    XCTAssertLessThanOrEqual(occupied + space.excursion * pose.extensionAmount, max(occupied, limit))
                    XCTAssertGreaterThanOrEqual(pose.extensionAmount, 0)
                }
            }
        }
    }
    func testPawLeadsHeadAndRetreatEndsAtZero() {
        let early = CatPose(elapsed: 0.3, active: true)
        XCTAssertGreaterThan(early.pawAmount, 0)
        XCTAssertEqual(early.headAmount, 0)
        XCTAssertEqual(early.extensionAmount, 0)
        let late = CatPose(elapsed: 8.15, active: true)
        XCTAssertEqual(late.headAmount, 0)
        XCTAssertGreaterThan(late.pawAmount, 0)
        let end = CatPose(elapsed: CatPose.duration, active: true)
        XCTAssertEqual(end.pawAmount, 0)
        XCTAssertEqual(end.headAmount, 0)
        XCTAssertEqual(end.extensionAmount, 0)
        XCTAssertEqual(CatPose(elapsed: 4, active: false).extensionAmount, 0)
    }
    func testCueCoalescingPriorityCooldownAndExpiry() {
        var queue = CatCueQueue()
        let now = Date()
        queue.enqueue(.completed, now: now)
        queue.enqueue(.attention, now: now)
        queue.enqueue(.completed, now: now)
        XCTAssertEqual(queue.take(now: now), .attention)
        XCTAssertNil(queue.take(now: now))
        queue.enqueue(.completed, now: now.addingTimeInterval(10))
        XCTAssertNil(queue.take(now: now.addingTimeInterval(10)))
        queue.enqueue(.completed, now: now.addingTimeInterval(31))
        XCTAssertNil(queue.take(now: now.addingTimeInterval(47)))
    }
}
