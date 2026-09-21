import XCTest
@testable import QuotaNotchCore

final class BubbleNotchLayoutTests: XCTestCase {
    func testClosedGlyphRequiresAConfiguredModeOrRetainedContent() {
        XCTAssertFalse(BubbleNotchLayout.shouldShowClosedGlyph(hasConfiguredReceiving: false, itemCount: 0))
        XCTAssertTrue(BubbleNotchLayout.shouldShowClosedGlyph(hasConfiguredReceiving: true, itemCount: 0))
        XCTAssertTrue(BubbleNotchLayout.shouldShowClosedGlyph(hasConfiguredReceiving: false, itemCount: 1))
        XCTAssertEqual(BubbleNotchLayout.visibleCount(for: 0), 0)
        XCTAssertEqual(BubbleNotchLayout.visibleCount(for: 5), 4)
    }

    func testCanonicalRectanglesStayInCountOrderAndMinimalUsesOneUniformTransform() {
        for count in BubbleNotchLayout.supportedCounts {
            let source = BubbleNotchLayout.rectangles(for: count)
            XCTAssertEqual(source.count, count)
            XCTAssertEqual(Set(source.map(\.id)).count, source.count)

            let fitted = BubbleNotchLayout.minimalPlacements(for: count)
            XCTAssertEqual(fitted.count, source.count)
            guard let firstSource = source.first, let firstFitted = fitted.first else { continue }
            let scale = firstFitted.width / firstSource.width
            for (original, result) in zip(source, fitted) {
                XCTAssertEqual(result.width / original.width, scale, accuracy: 0.000001)
                XCTAssertEqual(result.height / original.height, scale, accuracy: 0.000001)
                XCTAssertEqual(result.rotation, original.rotation)
                XCTAssertEqual(result.depth, original.depth)
                XCTAssertGreaterThanOrEqual(result.x - result.width / 2, 0)
                XCTAssertLessThanOrEqual(result.x + result.width / 2, BubbleNotchLayout.minimalWidth)
                XCTAssertGreaterThanOrEqual(result.y - result.height / 2, 0)
                XCTAssertLessThanOrEqual(result.y + result.height / 2, BubbleNotchLayout.minimalFilesHeight)
            }
            for a in source.indices {
                for b in source.indices where b > a {
                    let sourceDX = source[b].x - source[a].x
                    let sourceDY = source[b].y - source[a].y
                    let fittedDX = fitted[b].x - fitted[a].x
                    let fittedDY = fitted[b].y - fitted[a].y
                    XCTAssertEqual(fittedDX / sourceDX, scale, accuracy: 0.000001)
                    XCTAssertEqual(fittedDY / sourceDY, scale, accuracy: 0.000001)
                }
            }
        }
    }

    func testMinimalHeightShrinksUniformlyAtShortNotches() {
        XCTAssertLessThan(BubbleNotchLayout.minimalScale(closedHeight: 24), 1)
        XCTAssertEqual(BubbleNotchLayout.minimalScale(closedHeight: 32), 1)
        XCTAssertEqual(BubbleNotchLayout.minimalScale(closedHeight: 38), 1)
        XCTAssertGreaterThan(BubbleNotchLayout.minimalTotalHeight * BubbleNotchLayout.minimalScale(closedHeight: 24), 0)
        XCTAssertLessThanOrEqual(BubbleNotchLayout.minimalTotalHeight * BubbleNotchLayout.minimalScale(closedHeight: 24), 22)
    }

    func testLeftCompanionRecenterOffsetsOnlyItsAddedFootprint() {
        let widget = QuotaCompactMetrics.iconSize(height: 32)
        XCTAssertEqual(BubbleNotchLayout.addedLeftFootprint(widgetWidth: widget, hasExistingLeftModule: true), 26)
        XCTAssertEqual(BubbleNotchLayout.addedLeftFootprint(widgetWidth: widget, hasExistingLeftModule: false), widget)
        XCTAssertEqual(BubbleNotchLayout.centerCorrection(leftAdded: 26), -13)
        XCTAssertEqual(BubbleNotchLayout.centerCorrection(leftAdded: 26, rightAdded: 26), 0)
        XCTAssertEqual(BubbleNotchLayout.centerCorrection(leftAdded: 0, rightAdded: 26), 13)
    }

    func testReceiveOrbitStartsUpperLeftAndAcceleratesDownwardWithoutReverse() {
        let start = BubbleReceiveMotion.angle(at: 0)
        XCTAssertEqual(start, -3 * Double.pi / 4, accuracy: 0.0001)
        XCTAssertGreaterThan(BubbleReceiveMotion.speed(at: 1.5), BubbleReceiveMotion.speed(at: 0.5))
        XCTAssertGreaterThan(BubbleReceiveMotion.speed(at: 2), BubbleReceiveMotion.speed(at: 0))
        XCTAssertEqual(BubbleReceiveMotion.angle(at: 4) - start, 2 * Double.pi, accuracy: 0.0001)
        for t in stride(from: 0.0, to: 4.0, by: 0.01) {
            XCTAssertGreaterThan(BubbleReceiveMotion.speed(at: t), 0)
        }
    }

    func testScrollPolicyLocksToVerticalAxisAndUsesAccumulatedDirection() {
        XCTAssertTrue(BubbleScrollPolicy.isDominantVertical(deltaX: 0, deltaY: 1))
        XCTAssertTrue(BubbleScrollPolicy.isDominantVertical(deltaX: 2, deltaY: 3))
        XCTAssertFalse(BubbleScrollPolicy.isDominantVertical(deltaX: 4, deltaY: 3))
        XCTAssertFalse(BubbleScrollPolicy.isDominantVertical(deltaX: 0, deltaY: 0))
        XCTAssertTrue(BubbleScrollPolicy.isUpward(6))
        XCTAssertFalse(BubbleScrollPolicy.isUpward(-6))
        XCTAssertEqual(BubbleScrollPolicy.minimumDelta, 5)
    }

    func testScrollGestureReducerMatchesNativeToggleThresholdAndPhaseSequence() {
        var gesture = BubbleScrollGestureState()
        XCTAssertNil(gesture.update(deltaX: 0, deltaY: 0, phase: .began, isMomentum: false,
                                    timestamp: 1, lastClaimTimestamp: 0))
        XCTAssertNil(gesture.update(deltaX: 0, deltaY: 2, phase: .changed, isMomentum: false,
                                    timestamp: 1.05, lastClaimTimestamp: 0))
        XCTAssertEqual(gesture.update(deltaX: 0, deltaY: 3, phase: .changed, isMomentum: false,
                                      timestamp: 1.1, lastClaimTimestamp: 0), true)
        XCTAssertNil(gesture.update(deltaX: 0, deltaY: 8, phase: .changed, isMomentum: false,
                                    timestamp: 1.2, lastClaimTimestamp: 1.1))
        XCTAssertNil(gesture.update(deltaX: 0, deltaY: 8, phase: .changed, isMomentum: true,
                                    timestamp: 1.3, lastClaimTimestamp: 1.1))
        _ = gesture.update(deltaX: 0, deltaY: 0, phase: .ended, isMomentum: false,
                           timestamp: 1.4, lastClaimTimestamp: 1.1)
        XCTAssertEqual(gesture.update(deltaX: 0, deltaY: -5, phase: .none, isMomentum: false,
                                      timestamp: 2, lastClaimTimestamp: 1.1), false)
    }
}
