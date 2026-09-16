// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import QuotaNotchCore

final class TabSwipeNavigationTests: XCTestCase {
    func testSlowGestureAccumulatesAndMovesOnlyOnce() {
        var swipe = TabSwipeNavigation()
        XCTAssertNil(swipe.consume(x: -3, y: 0, at: 1, phase: .began))
        for index in 1...3 { XCTAssertNil(swipe.consume(x: -3, y: 0, at: 1 + Double(index) * 0.1, phase: .changed)) }
        XCTAssertEqual(swipe.consume(x: -3, y: 0, at: 1.4, phase: .changed), 1)
        XCTAssertNil(swipe.consume(x: -80, y: 0, at: 2.5, phase: .changed))
        XCTAssertNil(swipe.consume(x: -80, y: 0, at: 2.6, phase: .changed, momentum: true))
        XCTAssertNil(swipe.consume(x: 0, y: 0, at: 2.7, phase: .ended))
        XCTAssertEqual(swipe.consume(x: 16, y: 1, at: 3, phase: .began), -1)
    }
    func testVerticalAndDiagonalGesturesNeverSwitchPages() {
        var swipe = TabSwipeNavigation()
        XCTAssertNil(swipe.consume(x: 2, y: 18, at: 1, phase: .began))
        XCTAssertNil(swipe.consume(x: 50, y: 0, at: 1.1, phase: .changed))
        XCTAssertFalse(swipe.claimed)
        XCTAssertNil(swipe.consume(x: 15, y: 14, at: 2, phase: .began))
    }
    func testWheelBurstsAndCancellation() {
        var swipe = TabSwipeNavigation()
        XCTAssertEqual(swipe.consume(x: -2, y: 0, at: 1, phase: .none, precise: false), 1)
        XCTAssertNil(swipe.consume(x: -2, y: 0, at: 1.1, phase: .none, precise: false))
        XCTAssertEqual(swipe.consume(x: 2, y: 0, at: 1.5, phase: .none, precise: false), -1)
        XCTAssertNil(swipe.consume(x: -100, y: 0, at: 1.6, phase: .cancelled))
        XCTAssertFalse(swipe.claimed)
    }
    func testPageEdgesClampWithoutWrapping() {
        XCTAssertEqual(TabSwipeNavigation.destination(current: 0, step: -1, count: 3), 0)
        XCTAssertEqual(TabSwipeNavigation.destination(current: 0, step: 1, count: 3), 1)
        XCTAssertEqual(TabSwipeNavigation.destination(current: 1, step: 1, count: 3), 2)
        XCTAssertEqual(TabSwipeNavigation.destination(current: 2, step: 1, count: 3), 2)
    }
}
