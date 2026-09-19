// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import QuotaNotchCore

final class NotchCatTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    private func cue(_ id: String, _ action: CatAction, age: Double = 0) -> CatCue {
        CatCue(sessionID: id, eventID: id + action.rawValue, action: action, occurredAt: now.addingTimeInterval(-age))
    }
    func testEveryClipFitsTheSpaceWithoutStretchingPixels() {
        for height in [CGFloat(24), 26, 32, 38] {
            let widget = QuotaCompactMetrics.iconSize(height: height)
            let limit = widget + NotchModuleMetrics(widgetWidth: widget).additionalWidth
            for occupied in [CGFloat(0), widget, limit, limit + 10] {
                let space = CatWingSpace(occupied: occupied, limit: limit, height: height)
                for clip in [CatClips.gentle, CatClips.completed, CatClips.attention, CatClips.body, CatClips.watch, CatClips.doze] {
                    let scale = space.scale(body: clip.fullBody, backing: 2)
                    for step in clip.steps {
                        XCTAssertLessThanOrEqual(step.travel * scale, space.room)
                        XCTAssertEqual((scale * 2).rounded(), scale * 2)
                    }
                }
                if occupied >= limit { XCTAssertFalse(space.canPeek) }
                if occupied > 0 { XCTAssertFalse(space.canShowBody) }
            }
        }
    }
    func testClipsEnterAndExitHiddenAndUseOneStandingPose() {
        for clip in [CatClips.gentle, CatClips.completed, CatClips.attention, CatClips.body, CatClips.watch, CatClips.doze] {
            XCTAssertEqual(clip.steps.first?.travel, 0)
            XCTAssertEqual(clip.steps.last?.travel, 0)
            XCTAssertTrue(clip.steps.allSatisfy { $0.duration > 0 && $0.travel >= 0 })
            XCTAssertEqual(clip.step(at: clip.duration + 1).travel, 0)
        }
        XCTAssertFalse(CatClips.body.steps.contains { $0.asset == "Cat-body-sequence-0" })
    }
    func testInvalidEventsDoNotPlayAndDuplicateDoesNotExtendLifetime() {
        var queue = CatCueQueue()
        let waiting = cue("a", .attention)
        queue.enqueue(waiting, now: now)
        queue.enqueue(waiting, now: now.addingTimeInterval(14))
        XCTAssertNil(queue.take(now: now.addingTimeInterval(16), valid: { _ in true }))
        queue.enqueue(cue("b", .completed), now: now)
        XCTAssertNil(queue.take(now: now, valid: { _ in false }))
    }
    func testAttentionBypassesCompletionCooldownAndCoalescesBurst() {
        var queue = CatCueQueue()
        queue.enqueue(cue("a", .completed), now: now)
        XCTAssertEqual(queue.take(now: now, valid: { _ in true })?.action, .completed)
        queue.enqueue(cue("b", .completed), now: now)
        queue.enqueue(cue("c", .attention), now: now)
        XCTAssertEqual(queue.take(now: now, valid: { _ in true })?.action, .attention)
        XCTAssertTrue(queue.pending.isEmpty)
        queue.enqueue(cue("d", .attention), now: now)
        XCTAssertNil(queue.take(now: now.addingTimeInterval(1), valid: { _ in true }))
    }
    func testCompletionDoesNotRefreshWaitingEventAndClearingDropsHistory() {
        var queue = CatCueQueue()
        queue.enqueue(cue("a", .attention, age: 14), now: now)
        queue.enqueue(cue("b", .completed), now: now.addingTimeInterval(2))
        XCTAssertEqual(queue.take(now: now.addingTimeInterval(2), valid: { _ in true })?.action, .completed)
        queue.enqueue(cue("c", .attention), now: now)
        queue.clear()
        XCTAssertNil(queue.take(now: now, valid: { _ in true }))
    }
}
