import XCTest
@testable import QuotaNotchCore

final class NotchScrollRouterTests: XCTestCase {
    func testSharedNotchRouterAccumulatesSlowHorizontalAndConsumesDiagonalTail() {
        var router = NotchScrollRouter()
        XCTAssertEqual(router.update(deltaX: -2, deltaY: 0, phase: .none,
                                     isMomentum: false, timestamp: 1), .consume)
        XCTAssertEqual(router.update(deltaX: -2, deltaY: 0, phase: .none,
                                     isMomentum: false, timestamp: 1.05), .consume)
        XCTAssertEqual(router.update(deltaX: -2, deltaY: 0, phase: .none,
                                     isMomentum: false, timestamp: 1.10),
                       .horizontal(towardLeft: true))
        XCTAssertEqual(router.update(deltaX: 0, deltaY: 9, phase: .none,
                                     isMomentum: false, timestamp: 1.15), .consume)
        XCTAssertEqual(router.update(deltaX: 0, deltaY: 8, phase: .none,
                                     isMomentum: true, timestamp: 1.20), .consume)
        XCTAssertEqual(router.update(deltaX: 0, deltaY: 0, phase: .ended,
                                     isMomentum: false, timestamp: 1.25), .ended)
    }

    func testSharedNotchRouterKeepsVerticalFirstGestureOutOfHorizontalSwitch() {
        var router = NotchScrollRouter()
        XCTAssertEqual(router.update(deltaX: 0, deltaY: 2, phase: .began,
                                     isMomentum: false, timestamp: 2), .vertical)
        XCTAssertEqual(router.update(deltaX: 0, deltaY: 3, phase: .changed,
                                     isMomentum: false, timestamp: 2.05), .vertical)
        XCTAssertEqual(router.update(deltaX: -10, deltaY: 0, phase: .changed,
                                     isMomentum: false, timestamp: 2.10), .consume)

        var rightRouter = NotchScrollRouter()
        XCTAssertEqual(rightRouter.update(deltaX: 0, deltaY: 3, phase: .none,
                                          isMomentum: false, timestamp: 3,
                                          allowVertical: false), .vertical)
        XCTAssertEqual(rightRouter.update(deltaX: 2, deltaY: 0, phase: .none,
                                          isMomentum: false, timestamp: 4), .consume)
        XCTAssertEqual(rightRouter.update(deltaX: 2, deltaY: 0, phase: .none,
                                          isMomentum: false, timestamp: 4.05), .consume)
        XCTAssertEqual(rightRouter.update(deltaX: 2, deltaY: 0, phase: .none,
                                          isMomentum: false, timestamp: 4.10),
                       .horizontal(towardLeft: false))
    }
}
