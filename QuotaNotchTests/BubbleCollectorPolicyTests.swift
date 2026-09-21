import XCTest
@testable import QuotaNotchCore

final class BubbleCollectorPolicyTests: XCTestCase {
    func testFreshStartupDoesNotPersistPausedMode() {
        XCTAssertFalse(BubbleCollectorPolicy.shouldPersistPausedStartup(hasBeenConfigured: false))
        XCTAssertTrue(BubbleCollectorPolicy.shouldPersistPausedStartup(hasBeenConfigured: true))
    }

    func testSelectionRequiresChangedExternalNonSecureContent() {
        XCTAssertTrue(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, isSecureField: false,
            oldFingerprint: "before", newFingerprint: "after"
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, isSecureField: false,
            oldFingerprint: "same", newFingerprint: "same"
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, isSecureField: true,
            oldFingerprint: nil, newFingerprint: "secret"
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 7, ownProcessID: 7, isSecureField: false,
            oldFingerprint: nil, newFingerprint: "own app"
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: false, sourceProcessID: 42, ownProcessID: 7, isSecureField: false,
            oldFingerprint: nil, newFingerprint: "paused"
        ))
    }

    func testDragPreviewRequiresChangedSupportedExternalPasteboard() {
        XCTAssertTrue(BubbleCollectorPolicy.shouldPreviewDrag(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, pasteboardChanged: true,
            types: ["public.file-url"]
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPreviewDrag(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, pasteboardChanged: false,
            types: ["public.file-url"]
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPreviewDrag(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, pasteboardChanged: true,
            types: ["com.example.private-token"]
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPreviewDrag(
            receiving: true, sourceProcessID: 7, ownProcessID: 7, pasteboardChanged: true,
            types: ["public.utf8-plain-text"]
        ))
    }

    func testPanelFrameStaysOnNearestVisibleDisplayAndAwayFromAnchor() {
        let left = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let frame = BubbleCollectorGeometry.panelFrame(
            anchor: CGPoint(x: 1170, y: 430), size: CGSize(width: 150, height: 150),
            visibleFrames: [left, right]
        )
        XCTAssertTrue(right.contains(CGPoint(x: frame.minX, y: frame.minY)))
        XCTAssertLessThanOrEqual(frame.maxX, right.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, right.maxY)
        XCTAssertGreaterThanOrEqual(frame.minX, right.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, right.minY)
        XCTAssertNotEqual(frame.origin, CGPoint(x: 0, y: 0))
    }
}
