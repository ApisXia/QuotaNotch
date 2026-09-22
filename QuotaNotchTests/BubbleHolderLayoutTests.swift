// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import QuotaNotchCore

final class BubbleHolderLayoutTests: XCTestCase {
    func testPagesUseRealFourthAsPeekAndNextPageStartsThere() {
        let first = BubbleHolderLayout.page(for: 4, index: 0)
        XCTAssertEqual(first.clearCount, 3)
        XCTAssertEqual(first.peekIndex, 3)
        XCTAssertTrue(first.hasNext)

        let last = BubbleHolderLayout.page(for: 4, index: 1)
        XCTAssertEqual(last.clearCount, 1)
        XCTAssertNil(last.peekIndex)
        XCTAssertFalse(last.hasNext)
    }

    func testSmallCountsDoNotReserveThreeDeadCards() {
        for count in 0...3 {
            let page = BubbleHolderLayout.page(for: count, index: 0)
            if count == 0 {
                XCTAssertGreaterThanOrEqual(BubbleHolderLayout.rowWidth(for: page), 120)
            }
            let placements = BubbleHolderLayout.expandedPlacements(
                page: page,
                rowFrame: CGRect(x: 0, y: 0, width: 288, height: BubbleHolderLayout.rowHeight))
            XCTAssertEqual(placements.count, count)
            if !placements.isEmpty {
                let group = placements.map(\.frame)
                XCTAssertEqual(group.map(\.midX).reduce(0, +) / CGFloat(group.count), 144, accuracy: 0.1)
            }
        }
    }

    func testStackSourceMatchesApprovedCollectorGeometry() {
        let page = BubbleHolderLayout.page(for: 4, index: 0)
        let center = CGPoint(x: 41, y: 41)
        let placements = BubbleHolderLayout.collapsedPlacements(page: page, ballCenter: center)
        XCTAssertEqual(placements.count, 4)
        XCTAssertEqual(placements[0].rotation, -8, accuracy: 0.001)
        XCTAssertEqual(placements[3].rotation, 2, accuracy: 0.001)
        XCTAssertTrue(placements[3].isPeek)
        XCTAssertLessThan(placements[3].blur, 4)
    }

    func testExpandedGeometryClampsAndPreservesBallCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let center = CGPoint(x: 4, y: 896)
        let geometry = BubbleHolderLayout.panelGeometry(center: center, itemCount: 6,
                                                        expanded: true, visibleFrames: [screen])
        XCTAssertTrue(screen.contains(CGPoint(x: geometry.panelFrame.minX, y: geometry.panelFrame.minY)))
        XCTAssertGreaterThanOrEqual(geometry.panelFrame.minX, screen.minX)
        XCTAssertGreaterThanOrEqual(geometry.panelFrame.minY, screen.minY)
        let recoveredCenter = CGPoint(x: geometry.panelFrame.minX + geometry.ballCenter.x,
                                      y: geometry.panelFrame.maxY - geometry.ballCenter.y)
        XCTAssertEqual(recoveredCenter.x, center.x, accuracy: 0.1)
        XCTAssertEqual(recoveredCenter.y, center.y, accuracy: 0.1)
    }

    func testInterpolationKeepsStableSlotIdentity() {
        let page = BubbleHolderLayout.page(for: 4, index: 0)
        let source = BubbleHolderLayout.collapsedPlacements(page: page, ballCenter: CGPoint(x: 41, y: 41))
        let destination = BubbleHolderLayout.expandedPlacements(page: page,
            rowFrame: CGRect(x: 0, y: 0, width: 288, height: BubbleHolderLayout.rowHeight))
        let middle = BubbleHolderLayout.interpolate(source[2], destination[2], progress: 0.5)
        XCTAssertEqual(middle.slot, 2)
        XCTAssertEqual(middle.isPeek, false)
        XCTAssertGreaterThan(middle.frame.width, source[2].frame.width)
        XCTAssertLessThan(middle.frame.width, destination[2].frame.width)
    }
}
