import XCTest
@testable import QuotaNotchCore

final class QuotaMonitoringTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10000)
    func window(_ percent: Double, reset: Date? = nil) -> QuotaWindow {
        QuotaWindow(id: "primary", title: "Primary", remainingPercent: percent, resetsAt: reset)
    }
    func testStaleAfterSleepEvenWithoutNetworkError() {
        let result = QuotaResult(snapshot: QuotaSnapshot(windows: [window(50)], fetchedAt: now), failure: nil, nextAttempt: now.addingTimeInterval(300))
        XCTAssertFalse(result.isStale(provider: .codex, now: now.addingTimeInterval(300)))
        XCTAssertTrue(result.isStale(provider: .codex, now: now.addingTimeInterval(361)))
    }
    func testLowAndRecoveryDeduplicateWithinCycle() {
        var state = QuotaAlertState()
        let reset = now.addingTimeInterval(3600)
        XCTAssertEqual(state.observe(window(15, reset: reset), threshold: 20), [.low])
        XCTAssertEqual(state.observe(window(14, reset: reset), threshold: 20), [])
        XCTAssertEqual(state.observe(window(50, reset: reset), threshold: 20), [.recovered])
        XCTAssertEqual(state.observe(window(55, reset: reset), threshold: 20), [])
        XCTAssertEqual(state.observe(window(15, reset: reset), threshold: 20), [])
        XCTAssertEqual(state.observe(window(15, reset: reset.addingTimeInterval(3600)), threshold: 20), [.low])
    }
    func testAutomaticSelectionExcludesStaleReadings() {
        let a = QuotaPin(providerID: "claude", windowID: "primary")
        let b = QuotaPin(providerID: "codex", windowID: "primary")
        let results: [QuotaProvider: QuotaResult] = [
            .claude: QuotaResult(snapshot: QuotaSnapshot(windows: [window(1)], fetchedAt: now), failure: .network, nextAttempt: now),
            .codex: QuotaResult(snapshot: QuotaSnapshot(windows: [window(40)], fetchedAt: now), failure: nil, nextAttempt: now)
        ]
        XCTAssertEqual(QuotaAutomaticSelection.select(candidates: [a,b], results: results, now: now), b)
        XCTAssertNil(QuotaAutomaticSelection.select(candidates: [a], results: results, now: now))
    }
    func testPercentDoesNotClaimEmptyOrFullFromRounding() {
        XCTAssertEqual(QuotaText.percent(0.4), "<1")
        XCTAssertEqual(QuotaText.percent(0), "0")
        XCTAssertEqual(QuotaText.percent(99.8), "99")
        XCTAssertEqual(QuotaText.percent(100), "100")
    }
    func testResetRequiresServerConfirmation() {
        XCTAssertEqual(QuotaText.countdown(now.addingTimeInterval(-1), now: now), QuotaText.localized("等待重置确认"))
    }
}
