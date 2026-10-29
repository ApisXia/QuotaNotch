import XCTest
@testable import QuotaNotchCore

final class QuotaPetTests: XCTestCase {
    private let pets: [QuotaPetKind] = [.mochi, .bit, .jelly]

    func testWidgetFitsTheQuotaSlotAndMinimalFitsSixteenPoints() {
        for kind in pets {
            for mood in QuotaPetMood.allCases {
                for frame in 0...1 {
                    let widget = QuotaPetArt.sprite(kind, size: .widget, mood: mood, remaining: 64, frame: frame)
                    XCTAssertEqual(widget.width, 20, "\(kind) \(mood)")
                    XCTAssertEqual(widget.height, 16, "\(kind) \(mood)")
                    let minimal = QuotaPetArt.sprite(kind, size: .minimal, mood: mood, remaining: 64, frame: frame)
                    XCTAssertLessThanOrEqual(minimal.width, 16, "\(kind) \(mood)")
                    XCTAssertLessThanOrEqual(minimal.height, 12, "\(kind) \(mood)")
                }
            }
        }
        XCTAssertEqual(QuotaPetArt.sprite(.jelly, size: .minimal, mood: .idle, remaining: 50).width, 14)
    }

    /// Expected rows come from the approved design canvas.
    func testSpritesMatchTheApprovedDesign() {
        XCTAssertEqual(QuotaPetArt.sprite(.bit, size: .widget, mood: .working, remaining: 64, frame: 1).rows, [
            ".......o............", "......oLo...........", ".......o............", "..oooooooooooo......",
            ".occcccccccccco.....", "occkkkkkkkkkkcco....", "ockkkkkkkkkkkkco....", "ockkeekkkkeekkco....",
            "ockkkkkkekkkkkco....", "occkkkkkkkkkkcco....", ".occcccccccccco.....", "..oaaaaaaaaooo......",
            "...akkkkkkaso.......", "..oakeekkacoao......", "..sssssssssso.......", "....oo....oo........"
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .widget, mood: .refilled, remaining: 100, frame: 0).rows, [
            "..................w.", "..oo.......oo....www", ".ogo.......opo....w.", ".oggooooooooppo.....",
            ".oggcccccccccpo.....", "oggccccccccccco.w...", "occccocccccoccco....", "occcococccococco....",
            "ocpcccccccccpcco....", "occccccococcccco....", ".oscccccoccccsofff..", "..oosccccccsoo......",
            ".o.osccccccsoofffffo", "oco.scccccccsoBBBBBo", "oco.occocccoccoBBBo.", ".oooooooooooooo....."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.jelly, size: .widget, mood: .low, remaining: 12).rows, [
            "....................", "......oooooo........", "....ooccccccoo......", "...occcwwcccccod....",
            "..occcwcccccccddd...", "..occccccccccccd....", ".occcccccccccccco...", ".occcooccccooccco...",
            ".occceecccceeccco...", ".occcccccccccccco...", "occcccccooocccccco..", "occcccccccccccccco..",
            "oFFFFFFFFFFFFFFFFo..", ".offffffffffffffo...", "..oooooooooooooo....", "...................."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .widget, mood: .pacing, remaining: 41).rows, [
            "....................", "..oo.......oo...oo..", ".ogo.......opo.occo.", ".oggooooooooppoocco.",
            ".oggcccccccccpo.oco.", "oggceecccceecco..o..", "occceecccceeccco....", "occceecccceeccco....",
            "ocpcccccccccpcco....", "occcccccocccccco....", ".osccccomocccso.....", "..ooscccoccsoo......",
            ".o.osccccccsoofffffo", "oco.scccccccsoBBBBBo", "oco.occocccoccoBBBo.", ".oooooooooooooo....."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .minimal, mood: .idle, remaining: 72).rows, [
            "..oo.......oo...", ".ogo.......opo..", ".oggooooooooppo.", ".oggcccccccccpo.",
            "oggccccccccccco.", "occceecccceeccco", "occceecccceeccco", "ocpcccccccccpcco",
            "occccccococcccco", ".oscccccoccccso.", "................", ".ffffffffffxxxx."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.bit, size: .minimal, mood: .pacing, remaining: 41).rows, [
            "......oLo.......", ".......o........", "..oooooooooooo..", ".occcccccccccco.",
            "occkeekkkkeekcco", "ockkeekkkkeekkco", "ockkeekkkkeekkco", "ockkkkkkekkkkkco",
            "occkkkkemekkkcco", ".occccccoccccco.", "..oooooooooooo..", ".mmmmmmdddddddd."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.jelly, size: .minimal, mood: .refilled, remaining: 100).rows, [
            "....oooooo....", "..ooFFFFFFoo..", ".offffffffffo.", ".offffffffffo.", "offfoffffofffo",
            "offofoffofoffo", "offfffoofffffo", "offffffffffffo", ".offffffffffo.", "..oooooooooo.."
        ])
    }

    func testEveryDrawnPixelHasAColor() {
        for kind in pets {
            for tint in QuotaPetTint.allCases {
                for remaining in [0.0, 12, 30, 64, 100] {
                    let palette = QuotaPetArt.palette(kind, provider: .claude, tint: tint, remaining: remaining)
                    for mood in QuotaPetMood.allCases {
                        for size in [QuotaPetSize.widget, .minimal] {
                            for frame in 0...1 {
                                for blink in [false, true] {
                                    let sprite = QuotaPetArt.sprite(kind, size: size, mood: mood, remaining: remaining, frame: frame, blink: blink)
                                    for code in sprite.codes where code != UInt8(ascii: ".") {
                                        XCTAssertNotNil(palette[code], "\(kind) \(mood) \(Character(UnicodeScalar(code)))")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testGaugesFollowRemainingQuota() {
        func count(_ sprite: QuotaPetSprite, _ code: Character) -> Int {
            sprite.codes.filter { $0 == UInt8(ascii: code.unicodeScalars.first!) }.count
        }
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .widget, mood: .idle, remaining: 100), "m"), 12)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .widget, mood: .idle, remaining: 1), "m"), 2)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .widget, mood: .empty, remaining: 0), "m"), 0)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .minimal, mood: .idle, remaining: 50), "m"), 7)
        XCTAssertGreaterThan(count(QuotaPetArt.sprite(.jelly, size: .widget, mood: .idle, remaining: 90), "f"),
                             count(QuotaPetArt.sprite(.jelly, size: .widget, mood: .idle, remaining: 30), "f"))
        XCTAssertEqual(count(QuotaPetArt.sprite(.mochi, size: .widget, mood: .empty, remaining: 0), "f"), 0)
        XCTAssertGreaterThan(count(QuotaPetArt.sprite(.mochi, size: .minimal, mood: .idle, remaining: 80), "f"),
                             count(QuotaPetArt.sprite(.mochi, size: .minimal, mood: .idle, remaining: 20), "f"))
    }

    func testServiceTintAndWarningColors() {
        let claude = QuotaPetArt.palette(.bit, provider: .claude, tint: .service, remaining: 80)
        XCTAssertEqual(claude[UInt8(ascii: "e")], 0xE39B7A)
        let codex = QuotaPetArt.palette(.jelly, provider: .codex, tint: .service, remaining: 80)
        XCTAssertEqual(codex[UInt8(ascii: "f")], 0x9ED4BF)
        let original = QuotaPetArt.palette(.jelly, provider: .codex, tint: .original, remaining: 80)
        XCTAssertEqual(original[UInt8(ascii: "f")], 0x7AA2FF)
        XCTAssertEqual(QuotaPetArt.palette(.jelly, provider: .claude, tint: .original, remaining: 10)[UInt8(ascii: "f")], 0xFF5A4F)
        XCTAssertEqual(QuotaPetArt.palette(.bit, provider: .claude, tint: .original, remaining: 30)[UInt8(ascii: "L")], 0xF4D35E)
        XCTAssertEqual(QuotaPetArt.lighten(0x000000), 0x737373)
    }

    func testTrackerMoods() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let key = QuotaPetTracker.key(provider: .claude, windowID: "five_hour")
        func window(_ remaining: Double) -> QuotaWindow {
            QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: remaining, resetsAt: start.addingTimeInterval(4 * 3600))
        }
        var tracker = QuotaPetTracker()
        XCTAssertEqual(tracker.mood(key: key, window: nil, stale: false, now: start), .stale)
        XCTAssertEqual(tracker.mood(key: key, window: window(90), stale: true, now: start), .stale)
        tracker.observe(key: key, remaining: 95, at: start)
        XCTAssertEqual(tracker.mood(key: key, window: window(95), stale: false, now: start), .idle)
        tracker.observe(key: key, remaining: 93, at: start.addingTimeInterval(60))
        XCTAssertEqual(tracker.mood(key: key, window: window(93), stale: false, now: start.addingTimeInterval(120)), .working)
        XCTAssertEqual(tracker.mood(key: key, window: window(93), stale: false, now: start.addingTimeInterval(60 + 301)), .idle)
        XCTAssertEqual(tracker.mood(key: key, window: window(12), stale: false, now: start), .low)
        XCTAssertEqual(tracker.mood(key: key, window: window(0), stale: false, now: start), .empty)
        tracker.observe(key: key, remaining: 10, at: start.addingTimeInterval(500))
        tracker.observe(key: key, remaining: 100, at: start.addingTimeInterval(600))
        XCTAssertEqual(tracker.mood(key: key, window: window(100), stale: false, now: start.addingTimeInterval(603)), .refilled)
        XCTAssertEqual(tracker.mood(key: key, window: window(100), stale: false, now: start.addingTimeInterval(609)), .idle)
        // Older samples arriving late are ignored for change detection.
        tracker.observe(key: key, remaining: 50, at: start)
        XCTAssertEqual(tracker.mood(key: key, window: window(100), stale: false, now: start.addingTimeInterval(700)), .idle)
    }

    func testPaceWarning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Two hours into a five-hour window with 30% left: 70% used in 2h runs out in ~51 minutes, reset is in 3h.
        let fast = QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: 30, resetsAt: now.addingTimeInterval(3 * 3600))
        XCTAssertTrue(QuotaPace.runsOutBeforeReset(fast, now: now))
        let calm = QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: 70, resetsAt: now.addingTimeInterval(3 * 3600))
        XCTAssertFalse(QuotaPace.runsOutBeforeReset(calm, now: now))
        // Too early in the window to judge.
        let early = QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: 60, resetsAt: now.addingTimeInterval(5 * 3600 - 300))
        XCTAssertFalse(QuotaPace.runsOutBeforeReset(early, now: now))
        // Unknown length: no warning.
        let unknown = QuotaWindow(id: "primary_window", title: "主窗口", remainingPercent: 5, resetsAt: now.addingTimeInterval(3600))
        XCTAssertFalse(QuotaPace.runsOutBeforeReset(unknown, now: now))
        let codex = QuotaWindow(id: "primary_window", title: "5 小时", remainingPercent: 30, resetsAt: now.addingTimeInterval(3 * 3600), duration: 5 * 3600)
        XCTAssertTrue(QuotaPace.runsOutBeforeReset(codex, now: now))
        var tracker = QuotaPetTracker()
        tracker.observe(key: "claude:five_hour", remaining: 30, at: now)
        XCTAssertEqual(tracker.mood(key: "claude:five_hour", window: fast, stale: false, now: now), .pacing)
    }

    func testRedrawScheduleOnlyRunsFastWhileAnimating() {
        let date = Date(timeIntervalSinceReferenceDate: 1000.05)
        XCTAssertLessThan(QuotaPetArt.nextRedraw(after: date, mood: .working).timeIntervalSince(date), 0.43)
        let blink = QuotaPetArt.nextRedraw(after: date, mood: .idle)
        XCTAssertGreaterThan(blink.timeIntervalSince(date), 0)
        XCTAssertLessThanOrEqual(blink.timeIntervalSince(date), 4.01)
        XCTAssertEqual(QuotaPetArt.nextRedraw(after: date, mood: .empty).timeIntervalSince(date), 60, accuracy: 0.001)
        XCTAssertTrue(QuotaPetArt.blinking(at: Date(timeIntervalSinceReferenceDate: 1000.1)))
        XCTAssertFalse(QuotaPetArt.blinking(at: Date(timeIntervalSinceReferenceDate: 1001)))
    }

    func testCodexWindowKeepsItsLength() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":40,"limit_window_seconds":18000,"reset_after_seconds":3600}}}"#
        let snapshot = try QuotaParser.parse(Data(json.utf8), provider: .codex, now: Date())
        XCTAssertEqual(snapshot.windows.first?.period, 18000)
        XCTAssertEqual(QuotaWindow(id: "seven_day", title: "7 天", remainingPercent: 1, resetsAt: nil).period, 7 * 86400)
    }

    func testStoredKindFallsBackToDefault() {
        XCTAssertEqual(QuotaPetKind.stored(nil), .bit)
        XCTAssertEqual(QuotaPetKind.stored("jelly"), .jelly)
        XCTAssertEqual(QuotaPetKind.stored("unknown"), .bit)
        XCTAssertEqual(QuotaPetKind.stored("off"), .off)
    }
}
