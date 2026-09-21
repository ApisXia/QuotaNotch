import XCTest
@testable import QuotaNotchCore

final class BubbleCollectorMotionTests: XCTestCase {
    func testGatherHoldCollapseAndEnd() {
        XCTAssertEqual(BubbleCollectorMotion.frame(at: -0.1), .resting)
        let gather = BubbleCollectorMotion.frame(at: BubbleCollectorMotion.gatherDuration * 0.5)
        XCTAssertGreaterThan(gather.shellScale, 1)
        XCTAssertEqual(gather.shellOpacity, 1)
        let hold = BubbleCollectorMotion.frame(at: BubbleCollectorMotion.gatherDuration + BubbleCollectorMotion.holdDuration * 0.5)
        XCTAssertGreaterThan(hold.shellScale, 1)
        XCTAssertEqual(hold.shellOpacity, 1)
        let collapse = BubbleCollectorMotion.frame(at: BubbleCollectorMotion.gatherDuration + BubbleCollectorMotion.holdDuration + BubbleCollectorMotion.collapseDuration * 0.5)
        XCTAssertLessThan(collapse.shellScale, hold.shellScale)
        XCTAssertLessThan(collapse.contentOpacity, 1)
        let end = BubbleCollectorMotion.frame(at: BubbleCollectorMotion.totalDuration + 0.1)
        XCTAssertLessThan(end.shellOpacity, 0.01)
        XCTAssertLessThan(end.contentOpacity, 0.01)
    }
}
