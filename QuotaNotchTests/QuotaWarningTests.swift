import XCTest
@testable import QuotaNotchCore

final class QuotaWarningTests: XCTestCase {
    func testNormalQuotaHasNoWarning() {
        for p in [45.0, 70, 100] {
            let s = QuotaWarning(percent: p)
            XCTAssertEqual(s.yellow, 0); XCTAssertEqual(s.red, 0); XCTAssertEqual(s.glow, 0)
        }
    }
    func testFirstBandInterpolatesColorAndHalo() {
        let s = QuotaWarning(percent: 40)
        XCTAssertEqual(s.yellow, 0.5); XCTAssertEqual(s.red, 0)
        XCTAssertEqual(s.glow, 0.15, accuracy: 0.0001)
    }
    func testMiddleBandIsStableYellow() {
        for p in [35.0, 25, 15] {
            let s = QuotaWarning(percent: p)
            XCTAssertEqual(s.yellow, 1); XCTAssertEqual(s.red, 0)
            XCTAssertEqual(s.glow, 0.3, accuracy: 0.0001)
        }
    }
    func testCriticalBandInterpolatesAndSaturates() {
        XCTAssertEqual(QuotaWarning(percent: 10).red, 0.5)
        XCTAssertEqual(QuotaWarning(percent: 5).red, 1)
        XCTAssertEqual(QuotaWarning(percent: 2).red, 1)
    }
    func testEmptyQuotaKeepsVisibleWarningTrack() {
        let s = QuotaWarning(percent: 0)
        XCTAssertTrue(s.exhausted); XCTAssertEqual(s.fraction, 0)
        XCTAssertEqual(s.glow, 0.5, accuracy: 0.0001)
    }
    func testMissingNonfiniteAndOldDataNeverWarn() {
        let invalid: [Double?] = [nil, .nan, .infinity]
        for p in invalid {
            let s = QuotaWarning(percent: p)
            XCTAssertEqual(s.glow, 0); XCTAssertFalse(s.exhausted)
        }
        XCTAssertEqual(QuotaWarning(percent: 0, stale: true).glow, 0)
        XCTAssertFalse(QuotaWarning(percent: 0, stale: true).exhausted)
    }
    func testRecoveryRemovesWarningAndClampsValues() {
        XCTAssertEqual(QuotaWarning(percent: 120).fraction, 1)
        XCTAssertEqual(QuotaWarning(percent: -1).fraction, 0)
        XCTAssertEqual(QuotaWarning(percent: 100).glow, 0)
    }
    func testBandsAreContinuousAtTheirEdges() {
        for edge in [45.0, 35, 15, 5] {
            let a = QuotaWarning(percent: edge - 0.0001)
            let b = QuotaWarning(percent: edge + 0.0001)
            XCTAssertEqual(a.yellow, b.yellow, accuracy: 0.0001)
            XCTAssertEqual(a.red, b.red, accuracy: 0.0001)
            XCTAssertEqual(a.glow, b.glow, accuracy: 0.0001)
        }
    }
}

final class QuotaOpeningTests: XCTestCase {
    func testSingleTaskOwnsBothHalves() {
        for x in [-10.0, 10] {
            XCTAssertEqual(QuotaPresentation.quota.openingPage(pointerX: x, midpointX: 0, isOpen: false), .quota)
            XCTAssertEqual(QuotaPresentation.music.openingPage(pointerX: x, midpointX: 0, isOpen: false), .home)
        }
    }
    func testCombinedUsesScreenCenterIncludingCenterGap() {
        XCTAssertEqual(QuotaPresentation.combined.openingPage(pointerX: 499.9, midpointX: 500, isOpen: false), .home)
        XCTAssertEqual(QuotaPresentation.combined.openingPage(pointerX: 500, midpointX: 500, isOpen: false), .quota)
    }
    func testCrossingDuringHoverDelayUsesLatestPosition() {
        let current = QuotaPresentation.combined
        XCTAssertEqual(current.openingPage(pointerX: 490, midpointX: 500, isOpen: false), .home)
        XCTAssertEqual(current.openingPage(pointerX: 510, midpointX: 500, isOpen: false), .quota)
    }
    func testExpandedPagesNeverFollowPointer() {
        for p in [QuotaPresentation.music, .quota, .combined, .none] {
            for x in [-10.0, 10] { XCTAssertNil(p.openingPage(pointerX: x, midpointX: 0, isOpen: true)) }
        }
    }
    func testEmptyPresentationPreservesDefaultPage() {
        XCTAssertNil(QuotaPresentation.none.openingPage(pointerX: 10, midpointX: 0, isOpen: false))
    }
    func testSecondaryDisplayUsesItsOwnCoordinates() {
        XCTAssertEqual(QuotaPresentation.combined.openingPage(pointerX: -1200, midpointX: -1000, isOpen: false), .home)
        XCTAssertEqual(QuotaPresentation.combined.openingPage(pointerX: -800, midpointX: -1000, isOpen: false), .quota)
    }
}
