import XCTest
@testable import QuotaNotchCore

final class BubbleCollectorPolicyTests: XCTestCase {
    func testSelectedTextRangeExtractsOnlyTheBoundedSelection() {
        XCTAssertEqual(BubbleCollectorPolicy.selectedText(in: "abcdef", location: 1, length: 3), "bcd")
        XCTAssertNil(BubbleCollectorPolicy.selectedText(in: "abcdef", location: 1, length: 0))
        XCTAssertNil(BubbleCollectorPolicy.selectedText(in: "abcdef", location: -1, length: 2))
        XCTAssertNil(BubbleCollectorPolicy.selectedText(in: "abcdef", location: 5, length: 2))
        XCTAssertEqual(BubbleCollectorPolicy.selectedText(in: "A😀BC", location: 1, length: 2), "😀")
        XCTAssertNil(BubbleCollectorPolicy.selectedText(in: "A😀BC", location: 2, length: 1))
    }

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
        XCTAssertFalse(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, isSecureField: false,
            oldFingerprint: "same", newFingerprint: "same", hasVisiblePresentation: true
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, isSecureField: false,
            oldFingerprint: "same", newFingerprint: "same", hasVisiblePresentation: false,
            allowUnchangedSelection: false
        ))
        XCTAssertTrue(BubbleCollectorPolicy.shouldPresentSelection(
            receiving: true, sourceProcessID: 42, ownProcessID: 7, isSecureField: false,
            oldFingerprint: "same", newFingerprint: "same", hasVisiblePresentation: false,
            allowUnchangedSelection: true
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

    func testFinderAutomationRequiresExplicitOrPreviouslyGrantedConsent() {
        XCTAssertTrue(BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: true, frontmostBundleID: "com.apple.finder",
            explicitRequest: true, permissionGranted: false
        ))
        XCTAssertTrue(BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: true, frontmostBundleID: nil,
            explicitRequest: true, permissionGranted: false
        ))
        XCTAssertTrue(BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: true, frontmostBundleID: "com.apple.finder",
            explicitRequest: false, permissionGranted: true
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: true, frontmostBundleID: "com.apple.finder",
            explicitRequest: false, permissionGranted: false
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: false, frontmostBundleID: "com.apple.finder",
            explicitRequest: true, permissionGranted: false
        ))
        XCTAssertFalse(BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: true, frontmostBundleID: "com.apple.Safari",
            explicitRequest: false, permissionGranted: true
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
        XCTAssertLessThanOrEqual(frame.maxY, 430 - 24)
        XCTAssertNotEqual(frame.origin, CGPoint(x: 0, y: 0))
    }
}
