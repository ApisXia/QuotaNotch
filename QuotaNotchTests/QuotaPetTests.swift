import XCTest
@testable import QuotaNotchCore

final class QuotaPetTests: XCTestCase {
    private let pets = QuotaPetKind.pets

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
        XCTAssertEqual(QuotaPetArt.sprite(.bit, size: .widget, mood: .idle, remaining: 72).rows, [
            ".........o..........", "........oLo.........", ".........o..........", "....oooooooooooo....",
            "...occcccccccccco...", "..occkeekkkkeekcco..", "..ockkeekkkkeekkco..", "..ockkeekkkkeekkco..",
            "..ockkkkkkkkkkkkco..", "..occkkkkeekkkkcco..", "...occcccccccccco...", "....oooooooooooo....",
            "....osmmmmmmddso....", "...oasmmmmmmddsao...", "....osssssssssso....", "......oo....oo......"
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .widget, mood: .idle, remaining: 72, frame: 0).rows, [
            "....................", "..oo.......oo.......", ".ogo.......opo......", ".oggooooooooppo.....",
            ".oggcccccccccpo.....", "oggcweccccewcco.....", "occceecccceeccco....", "occccccppccccccS.S..",
            "ocpccocoococcpSoS...", "occcccoccocccGGGGGG.", ".osccccccwcccGvvvvG.", "..oosccccccsoGFFFFGG",
            ".o.osccccccsoGffffGG", "oco.scccccccsGffffGG", "oco.occocccocGffffG.", ".oooooooooooooGGGG.."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .widget, mood: .refilled, remaining: 100, frame: 0).rows, [
            ".................w..", "..oo.......oo...www.", ".ogo.......opo...w..", ".oggooooooooppo.....",
            ".oggeccccccecpo.....", "oggccecccceccco.....", "occcecccccceccco.w..", "occccccppccccccS.S..",
            "ocpccocoococcpSoS...", "occcccoTTocccGGGGGG.", ".osccccccwcccGFFFFG.", "..oosccccccsoGffffGG",
            ".o.osccccccsoGffffGG", "oco.scccccccsGffffGG", "oco.occocccocGffffG.", ".oooooooooooooGGGG.."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.jelly, size: .widget, mood: .low, remaining: 12).rows, [
            "....................", ".......oooooo.......", ".....ooccccccoo..f..", "....occcwwcccccofff.",
            "...occcwccccccccof..", "...occcccccccccco...", "..occcccccccccccco..", "..occcooccccooccco..",
            "..occceecccceeccco..", "..ocpccccccccccpco..", ".occcccccMMccccccco.", ".occcccccccccccccco.",
            ".oFFFFFFFFFFFFFFFFo.", "..offffffffffffffo..", "...oooooooooooooo...", "...................."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.ghost, size: .widget, mood: .idle, remaining: 72).rows, [
            "....................", "........oooo........", "......ooccccoo......", ".....hhccccccco.....",
            "....ohccccccccso....", "...occccccccccsso...", "...occceccccecsso...", "...occceccccecsso...",
            "...ocpccccccccpso...", ".ooocccccMMcccssooo.", ".ococcccccccccssoso.", "...occccccccccsso...",
            "...ossosssosssoso...", "...oso.oso.oso.oo...", "....oo..oo..oo..o...", "...................."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.ghost, size: .widget, mood: .needsYou, remaining: 41, frame: 1).rows, [
            "....................", "........oooo........", "......ooccccoo....X.", ".....hhccccccco...X.",
            "....ohccccccccso....", "...occceccccecsso.X.", "...occceccccecsso...", "...occceccccecsso...",
            "...ocpccccccccpso...", ".ooocccccMMcccssooo.", ".ococccccMMcccssoso.", "...occccccccccsso...",
            "...oosssosssossso...", "...o.oso.oso.oso....", "...o..oo..oo..oo....", "...................."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.sprout, size: .widget, mood: .needsYou, remaining: 41).rows, [
            "....................", ".......oo..oo.......", "......olo..olo......", "......olo..olo...X..",
            "......oLoggoLo...X..", ".......ooggoo.......", ".........gg......X..", ".........gg.........",
            "...oooooooooooooo...", "...orrrrrrrrrrrro...", "....occeccccecco....", "....occeccccecco....",
            "....opceccccecpo....", "....occccMMcccco....", ".....ommmnnnnno.....", ".....oooooooooo....."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.sprout, size: .widget, mood: .low, remaining: 12).rows, [
            "....................", "....................", "....................", "........oooo........",
            ".......oyggyo.......", ".....oyyoggoyyo..d..", "....oyyo.gg.oyyoddd.", "....oo...gg...oo.d..",
            "...oooooooooooooo...", "...orrrrrrrrrrrro...", "....ococcccccoco....", "....occeccccecco....",
            "....opccccccccpo....", "....occccMMcccco....", ".....omnnnnnnno.....", ".....oooooooooo....."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .widget, mood: .needsYou, remaining: 41).rows, [
            "....................", "..oo.......oo...oo..", ".ogo.......opo.occo.", ".oggooooooooppoocco.",
            ".oggweccccewcpo.oco.", "oggceecccceecco..o..", "occceecccceeccco....", "occccccppcccccco....",
            "ocpccccooccccpco....", "occcccoMMocccGGGGGG.", ".osccccooccccGvvvvG.", "..oosccccccsoGvvvvGG",
            ".o.osccccccsoGvvvvGG", "oco.scccccccsGFFFFGG", "oco.occocccocGffffG.", ".oooooooooooooGGGG.."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.mochi, size: .minimal, mood: .idle, remaining: 72).rows, [
            "..oo.......oo...", ".ogo.......opo..", ".oggooooooooppo.", ".oggcccccccccpo.",
            "oggcweccccewcco.", "occceecccceeccco", "occccccppcccccco", "ocpccocoococcpco",
            "occcccoccoccccco", ".osccccccwcccso.", "................", ".ffffffffffxxxx."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.bit, size: .minimal, mood: .needsYou, remaining: 41).rows, [
            "......oLo.......", ".......o........", "..oooooooooooo..", ".occcccccccccco.",
            "occkeekkkkeekcco", "ockkeekkkkeekkco", "ockkkkkkkkkkkkco", "ockkeekkkkeekkco",
            "occkkkkkkkkkkcco", ".occcccccccccco.", "..oooooooooooo..", ".mmmmmmdddddddd."
        ])
        XCTAssertEqual(QuotaPetArt.sprite(.jelly, size: .minimal, mood: .refilled, remaining: 100).rows, [
            "....oooooo....", "..ooFFFFFFoo..", ".offffffffffo.", ".offffffffffo.", "offfoffffofffo",
            "offofoffofoffo", "offfffoofffffo", "offffffffffffo", ".offffffffffo.", "..oooooooooo.."
        ])
    }

    func testTasksDriveThePoseAndWaitingWins() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var tasks = QuotaPetTasks(waiting: 1, running: 2)
        XCTAssertTrue(QuotaPetBehavior.resolve(quota: .low, tasks: tasks, now: now) == (.needsYou, .waiting))
        tasks.waiting = 0
        XCTAssertTrue(QuotaPetBehavior.resolve(quota: .idle, tasks: tasks, now: now) == (.working, .running))
        XCTAssertTrue(QuotaPetBehavior.resolve(quota: .empty, tasks: tasks, now: now) == (.empty, .none))
        tasks.running = 0; tasks.lastCompletedAt = now.addingTimeInterval(-2)
        XCTAssertTrue(QuotaPetBehavior.resolve(quota: .low, tasks: tasks, now: now) == (.celebrate, .none))
        XCTAssertTrue(QuotaPetBehavior.resolve(quota: .low, tasks: tasks, now: now.addingTimeInterval(10)) == (.low, .none))
        XCTAssertTrue(QuotaPetBehavior.resolve(quota: .stale, tasks: .none, now: now) == (.stale, .none))
    }

    func testPacingNoLongerTapsTheGlass() {
        let pacing = QuotaPetArt.sprite(.mochi, size: .widget, mood: .pacing, remaining: 41)
        let waiting = QuotaPetArt.sprite(.mochi, size: .widget, mood: .needsYou, remaining: 41)
        XCTAssertNotEqual(pacing, waiting)
        XCTAssertEqual(pacing.rows[1], "..oo.......oo.......")
    }

    func testContoursFollowTheOutline() {
        let sprite = QuotaPetArt.sprite(.jelly, size: .widget, mood: .idle, remaining: 50)
        let rings = sprite.contours(maxDistance: 3)
        XCTAssertEqual(rings.count, 3)
        for (index, ring) in rings.enumerated() {
            XCTAssertFalse(ring.isEmpty)
            for cell in ring { XCTAssertFalse(sprite.isFilled(cell.x, cell.y), "ring \(index)") }
        }
        // The first ring touches the art; outer rings are farther out and larger.
        XCTAssertTrue(rings[0].allSatisfy { c in [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { sprite.isFilled(c.x + $0.0, c.y + $0.1) } })
        XCTAssertGreaterThan(rings[2].count, rings[0].count)
        XCTAssertFalse(sprite.outlineCells.isEmpty)
        XCTAssertTrue(sprite.outlineCells.allSatisfy { sprite.code(x: $0.x, y: $0.y) == UInt8(ascii: "o") })
    }

    func testEachPetHasItsOwnThemeColor() {
        XCTAssertEqual(Set(QuotaPetKind.pets.map { QuotaPetArt.themeColor($0) }).count, QuotaPetKind.pets.count)
        // Tinted by service, the effects take the service's color.
        XCTAssertEqual(QuotaPetArt.themeColor(.bit, provider: .claude, tint: .service), QuotaPetArt.brandColor(.claude))
        XCTAssertEqual(QuotaPetArt.themeColor(.bit, provider: .codex, tint: .original), QuotaPetArt.themeColor(.bit))
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
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .widget, mood: .idle, remaining: 100), "m"), 16)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .widget, mood: .idle, remaining: 1), "m"), 2)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .widget, mood: .empty, remaining: 0), "m"), 0)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bit, size: .minimal, mood: .idle, remaining: 50), "m"), 7)
        XCTAssertGreaterThan(count(QuotaPetArt.sprite(.jelly, size: .widget, mood: .idle, remaining: 90), "f"),
                             count(QuotaPetArt.sprite(.jelly, size: .widget, mood: .idle, remaining: 30), "f"))
        XCTAssertEqual(count(QuotaPetArt.sprite(.mochi, size: .widget, mood: .empty, remaining: 0), "f"), 0)
        XCTAssertEqual(count(QuotaPetArt.sprite(.sprout, size: .widget, mood: .idle, remaining: 100), "m"), 8)
        XCTAssertEqual(count(QuotaPetArt.sprite(.sprout, size: .widget, mood: .empty, remaining: 0), "m"), 0)
        // The ghost's body fades toward black as quota is used; its outline stays.
        let solid = QuotaPetArt.palette(.ghost, provider: .claude, tint: .original, remaining: 100)
        let faint = QuotaPetArt.palette(.ghost, provider: .claude, tint: .original, remaining: 10)
        XCTAssertEqual(solid[UInt8(ascii: "c")], 0xF6F7FF)
        XCTAssertLessThan(faint[UInt8(ascii: "c")]! & 0xFF, solid[UInt8(ascii: "c")]! & 0xFF)
        XCTAssertEqual(faint[UInt8(ascii: "o")], solid[UInt8(ascii: "o")])
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

    func testSavedPetFallsBackToTheDefault() {
        XCTAssertEqual(QuotaPetKind.choice(nil), .bit)
        XCTAssertEqual(QuotaPetKind.choice("jelly"), .jelly)
        XCTAssertEqual(QuotaPetKind.choice("ghost"), .ghost)
        XCTAssertEqual(QuotaPetKind.choice("sprout"), .sprout)
        XCTAssertEqual(QuotaPetKind.choice("fish"), .fish)
        XCTAssertEqual(QuotaPetKind.choice("pear"), .pear)
        XCTAssertEqual(QuotaPetKind.choice("bbq"), .bbq)
        XCTAssertEqual(QuotaPetKind.choice("ox"), .ox)
        XCTAssertEqual(QuotaPetKind.choice("unknown"), .bit)
        XCTAssertEqual(QuotaPetKind.choice("off"), .bit)
        XCTAssertEqual(QuotaPetKind.allCases, QuotaPetKind.pets)
    }

    func testPixelScaleStaysOnWholeDevicePixels() {
        XCTAssertEqual(QuotaPetArt.pixelScale(size: .standard, notchHeight: 32, displayScale: 2), 1.5)
        XCTAssertEqual(QuotaPetArt.pixelScale(size: .standard, notchHeight: 32, displayScale: 1), 1)
        XCTAssertEqual(QuotaPetArt.pixelScale(size: .small, notchHeight: 32, displayScale: 2), 1)
        XCTAssertEqual(QuotaPetArt.pixelScale(size: .large, notchHeight: 32, displayScale: 2), 1.5)
        XCTAssertEqual(QuotaPetArt.pixelScale(size: .large, notchHeight: 38, displayScale: 1), 2)
        XCTAssertEqual(QuotaPetArt.pixelScale(size: .large, notchHeight: 24, displayScale: 2), 1)
        for size in NotchUISize.allCases {
            for height: CGFloat in [24, 32, 38] {
                for display: CGFloat in [1, 2] {
                    let scale = QuotaPetArt.pixelScale(size: size, notchHeight: height, displayScale: display)
                    XCTAssertEqual((scale * display).truncatingRemainder(dividingBy: 1), 0)
                    XCTAssertLessThanOrEqual(16 * scale, height)
                }
            }
        }
    }

    func testGaugeColorFollowsThePet() {
        XCTAssertEqual(QuotaPetArt.gaugeColor(.mochi, provider: .claude, tint: .original, remaining: 80), 0xF0B85A)
        XCTAssertEqual(QuotaPetArt.gaugeColor(.mochi, provider: .claude, tint: .service, remaining: 80), 0xE39B7A)
        XCTAssertEqual(QuotaPetArt.gaugeColor(.bit, provider: .codex, tint: .original, remaining: 80), 0x5AD19A)
        XCTAssertEqual(QuotaPetArt.gaugeColor(.bit, provider: .codex, tint: .service, remaining: 80), 0x9ED4BF)
        XCTAssertEqual(QuotaPetArt.gaugeColor(.jelly, provider: .claude, tint: .original, remaining: 80), 0x7AA2FF)
        XCTAssertEqual(QuotaPetArt.gaugeColor(.jelly, provider: .claude, tint: .original, remaining: 10), 0xFF5A4F)
        XCTAssertEqual(QuotaPetArt.gaugeColor(.mochi, provider: .claude, tint: .original, remaining: 30), 0xF4D35E)
    }

    func testSizeSettingMigratesLargerDisplay() {
        XCTAssertEqual(NotchUISize.stored(nil, legacyComfortable: true), .large)
        XCTAssertEqual(NotchUISize.stored(nil, legacyComfortable: false), .standard)
        XCTAssertEqual(NotchUISize.stored("small", legacyComfortable: true), .small)
        XCTAssertEqual(NotchUISize.standard.panelScale, 1)
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32, size: .standard), QuotaCompactMetrics.iconSize(height: 32))
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32, size: .large), QuotaCompactMetrics.iconSize(height: 32, comfortable: true))
    }

    func testPeekFiresAtKeyMoments() {
        XCTAssertNil(QuotaPeekRule.event(previous: nil, current: 10, wasPacing: false, pacing: true))
        XCTAssertNil(QuotaPeekRule.event(previous: 64, current: 60, wasPacing: false, pacing: false))
        XCTAssertEqual(QuotaPeekRule.event(previous: 52, current: 49, wasPacing: false, pacing: false), .crossed(50))
        XCTAssertEqual(QuotaPeekRule.event(previous: 55, current: 15, wasPacing: false, pacing: false), .crossed(20))
        XCTAssertEqual(QuotaPeekRule.event(previous: 3, current: 0, wasPacing: false, pacing: false), .crossed(0))
        XCTAssertEqual(QuotaPeekRule.event(previous: 5, current: 100, wasPacing: true, pacing: false), .refilled)
        XCTAssertEqual(QuotaPeekRule.event(previous: 70, current: 68, wasPacing: false, pacing: true), .pacing)
        XCTAssertNil(QuotaPeekRule.event(previous: 70, current: 68, wasPacing: true, pacing: true))
        XCTAssertNil(QuotaPeekRule.event(previous: 49, current: 51, wasPacing: false, pacing: false))
    }

    /// Faces sit exactly on the pet's center line.
    func testNewFacesAreSymmetric() {
        let face = Set("eoWMT".utf8)
        for (kind, center, rows) in [(QuotaPetKind.ghost, 9.5, 5...9), (.sprout, 9.5, 10...13), (.jelly, 9.5, 5...10), (.bit, 9.5, 5...9)] {
            for mood in [QuotaPetMood.idle, .working, .pacing, .stale, .empty, .refilled] {
                let sprite = QuotaPetArt.sprite(kind, size: .widget, mood: mood, remaining: 72)
                for y in rows {
                    for x in 0..<sprite.width {
                        let mirror = Int(2 * center) - x
                        guard mirror >= 0, mirror < sprite.width, face.contains(sprite.code(x: x, y: y)),
                              x > 3, x < sprite.width - 4 else { continue }
                        if [UInt8(ascii: "M"), UInt8(ascii: "T")].contains(sprite.code(x: x, y: y)) {
                            XCTAssertEqual(sprite.code(x: mirror, y: y), sprite.code(x: x, y: y), "\(kind) \(mood) \(x),\(y)")
                        }
                    }
                }
            }
        }
    }

    func testUpscaledSpriteKeepsItsShape() {
        let sprite = QuotaPetArt.sprite(.bit, size: .widget, mood: .idle, remaining: 64)
        let big = sprite.upscaled(2)
        XCTAssertEqual(big.width, 40)
        XCTAssertEqual(big.height, 32)
        for y in 0..<sprite.height { for x in 0..<sprite.width {
            XCTAssertEqual(big.code(x: 2 * x + 1, y: 2 * y + 1), sprite.code(x: x, y: y))
        } }
        XCTAssertEqual(sprite.upscaled(1), sprite)
    }

    /// Every pet fills the grid around its middle, so effects center on the body.
    func testPetsAreCenteredInTheGrid() {
        for kind in pets {
            let sprite = QuotaPetArt.sprite(kind, size: .widget, mood: .stale, remaining: 64)
            let filled = (0..<sprite.width).filter { x in (0..<sprite.height).contains { sprite.isFilled(x, $0) } }
            let middle = Double(filled.first! + filled.last!) / 2
            XCTAssertEqual(middle, 9.5, accuracy: 0.6, "\(kind)")
        }
    }

    /// One click pets; the third within 2.5 s annoys; the fifth makes it dizzy and starts over.
    func testClicksPickTheReaction() {
        var touch = QuotaPetTouch()
        let start = Date(timeIntervalSince1970: 1_000)
        let reactions = (0..<6).map { touch.tap(at: start.addingTimeInterval(Double($0) * 0.3), asleep: false, waiting: false) }
        XCTAssertEqual(reactions, [.pat, .pat, .annoyed, .annoyed, .dizzy, .pat])
        // Clicks further apart than the window are each a single pat.
        var slow = QuotaPetTouch()
        XCTAssertEqual((0..<4).map { slow.tap(at: start.addingTimeInterval(Double($0) * 3), asleep: false, waiting: false) },
                       [.pat, .pat, .pat, .pat])
        // Asleep, it stirs twice and wakes on the third click; a waiting task always opens.
        var sleepy = QuotaPetTouch()
        XCTAssertEqual((0..<3).map { sleepy.tap(at: start.addingTimeInterval(Double($0) * 0.4), asleep: true, waiting: false) },
                       [.stir, .stir, .pat])
        var busy = QuotaPetTouch()
        XCTAssertEqual(busy.tap(at: start, asleep: false, waiting: true), .open)
    }

    func testReactionPosesStayNearThePetAndSettle() {
        for kind in pets {
            for reaction in [QuotaPetReaction.pat, .annoyed, .dizzy, .stir, .open] {
                var t = 0.0
                while t < reaction.duration {
                    let pose = QuotaPetTouchPose.at(reaction, pet: kind, elapsed: t)
                    XCTAssertLessThanOrEqual(abs(pose.dx), 1, "\(kind) \(reaction)")
                    XCTAssertLessThanOrEqual(abs(pose.dy), 3, "\(kind) \(reaction)")
                    XCTAssertLessThanOrEqual(abs(pose.rotation), 6.01, "\(kind) \(reaction)")
                    for particle in pose.particles {
                        XCTAssert((0...1).contains(particle.opacity), "\(kind) \(reaction)")
                        XCTAssert(particle.sprite.codes.allSatisfy { $0 == UInt8(ascii: ".") || QuotaPetParticle.palette[$0] != nil })
                    }
                    t += 0.05
                }
                let calm = QuotaPetTouchPose.at(reaction, pet: kind, elapsed: t, reduceMotion: true)
                XCTAssertEqual([calm.dx, calm.dy, calm.rotation], [0, 0, 0])
                XCTAssertFalse(calm.flipped)
            }
        }
    }

    /// The fish's water is the quota; the pear's mountain grows as quota runs out.
    func testFishWaterAndPearMountainFollowQuota() {
        func count(_ sprite: QuotaPetSprite, _ codes: String) -> Int {
            let set = Set(codes.utf8)
            return sprite.codes.filter { set.contains($0) }.count
        }
        let water = { (q: Double) in count(QuotaPetArt.sprite(.fish, size: .widget, mood: .idle, remaining: q), "uU") }
        XCTAssertGreaterThan(water(90), water(40))
        XCTAssertGreaterThan(water(40), water(5))
        XCTAssertEqual(water(0), 0)
        let mountain = { (q: Double) in count(QuotaPetArt.sprite(.pear, size: .widget, mood: .idle, remaining: q), "rRW") }
        XCTAssertEqual(mountain(90), 0)
        XCTAssertGreaterThan(mountain(60), 0)
        XCTAssertGreaterThan(mountain(40), mountain(60))
        XCTAssertGreaterThan(mountain(20), mountain(40))
        XCTAssertGreaterThan(mountain(5), mountain(20))
        // The sausage chars as quota runs out; the cart fills with boxes.
        XCTAssertEqual(QuotaPetArt.doneness(100), 0)
        XCTAssertEqual(QuotaPetArt.doneness(0), 5)
        XCTAssertGreaterThan(count(QuotaPetArt.sprite(.bbq, size: .widget, mood: .empty, remaining: 0), "x"), 0)
        XCTAssertEqual(count(QuotaPetArt.sprite(.bbq, size: .widget, mood: .idle, remaining: 70), "x"), 0)
        let boxes = { (q: Double) in count(QuotaPetArt.sprite(.ox, size: .widget, mood: .idle, remaining: q), "Bb") }
        XCTAssertEqual(boxes(100), 0)
        XCTAssertGreaterThan(boxes(50), boxes(90))
        XCTAssertGreaterThan(boxes(5), boxes(50))
        XCTAssertEqual(count(QuotaPetArt.sprite(.ox, size: .widget, mood: .refilled, remaining: 30), "Bb"), 0)
        // Just refilled, the mountain is gone whatever the number says.
        XCTAssertEqual(count(QuotaPetArt.sprite(.pear, size: .widget, mood: .refilled, remaining: 30), "rRW"), 0)
    }

    /// The fish and the pear act clicks out inside their art; every moment stays on the grid,
    /// is fully colored, and goes back to the plain pet when the reaction ends.
    func testFishAndPearActOutClicks() {
        for kind in [QuotaPetKind.fish, .pear, .bbq, .ox] {
            for (reaction, mood, remaining) in [(QuotaPetReaction.pat, QuotaPetMood.idle, 70.0), (.annoyed, .idle, 70), (.dizzy, .idle, 20),
                                                (.stir, .empty, 0), (.open, .needsYou, 41), (.pat, .idle, 90), (.pat, .empty, 0)] {
                let palette = QuotaPetArt.palette(kind, provider: .codex, tint: .original, remaining: remaining)
                let plain = QuotaPetArt.sprite(kind, size: .widget, mood: mood, remaining: remaining)
                var changed = false
                for still in [false, true] {
                    var t = 0.0
                    while t < reaction.duration {
                        let moment = QuotaPetTouchMoment(reaction: reaction, elapsed: t, reduceMotion: still)
                        let sprite = QuotaPetArt.sprite(kind, size: .widget, mood: mood, remaining: remaining, touch: moment)
                        XCTAssertEqual([sprite.width, sprite.height], [20, 16], "\(kind) \(reaction)")
                        for code in sprite.codes where code != UInt8(ascii: ".") {
                            XCTAssertNotNil(palette[code], "\(kind) \(reaction) \(Character(UnicodeScalar(code)))")
                        }
                        if sprite != plain { changed = true }
                        t += 0.05
                    }
                }
                XCTAssertTrue(changed, "\(kind) \(reaction) \(mood)")
                let after = QuotaPetTouchMoment(reaction: reaction, elapsed: reaction.duration + 0.01)
                XCTAssertEqual(QuotaPetArt.sprite(kind, size: .widget, mood: mood, remaining: remaining, touch: after), plain)
            }
        }
    }

    /// A finished task plays the pet's own celebration; an idle pet makes a small move now and then.
    func testPetsActOnTheirOwn() {
        let dot = UInt8(ascii: ".")
        let done = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(QuotaPetMotion.moment(mood: .celebrate, completedAt: done, at: done.addingTimeInterval(1))?.reaction, .cheer)
        XCTAssertNil(QuotaPetMotion.moment(mood: .celebrate, completedAt: done, at: done.addingTimeInterval(3)))
        XCTAssertNil(QuotaPetMotion.moment(mood: .working, completedAt: done, at: done))
        let quiet = (0..<90).compactMap { QuotaPetMotion.moment(mood: .idle, completedAt: nil, at: done.addingTimeInterval(Double($0))) }
        XCTAssertFalse(quiet.isEmpty)
        XCTAssertLessThan(quiet.count, 10)
        XCTAssertTrue(quiet.allSatisfy { $0.reaction == .idleMove })
        let start = Date(timeIntervalSinceReferenceDate: 45 * 1000 + 10)
        XCTAssertEqual(QuotaPetMotion.nextFrame(after: start, mood: .idle, completedAt: nil)?.timeIntervalSinceReferenceDate ?? 0,
                       45 * 1001 + 0.001, accuracy: 0.01)
        XCTAssertNil(QuotaPetMotion.nextFrame(after: start, mood: .working, completedAt: nil))
        for kind in pets {
            for reaction in [QuotaPetReaction.cheer, .idleMove] {
                let mood: QuotaPetMood = reaction == .cheer ? .celebrate : .idle
                let palette = QuotaPetArt.palette(kind, provider: .claude, tint: .original, remaining: 72)
                var t = 0.0
                while t < reaction.duration {
                    let pose = QuotaPetTouchPose.at(reaction, pet: kind, elapsed: t, remaining: 72)
                    let sprite = QuotaPetArt.sprite(kind, size: .widget, mood: pose.mood ?? mood, remaining: 72,
                                                    touch: .init(reaction: reaction, elapsed: t))
                    XCTAssertEqual([sprite.width, sprite.height], [20, 16], "\(kind) \(reaction)")
                    for code in sprite.codes where code != dot {
                        XCTAssertNotNil(palette[code], "\(kind) \(reaction) \(Character(UnicodeScalar(code)))")
                    }
                    for particle in pose.particles {
                        XCTAssert((0...1).contains(particle.opacity), "\(kind) \(reaction)")
                        XCTAssert(particle.sprite.codes.allSatisfy { $0 == dot || QuotaPetParticle.palette[$0] != nil }, "\(particle.kind)")
                    }
                    XCTAssertLessThanOrEqual(abs(pose.dy), 5, "\(kind) \(reaction)")
                    t += 0.1
                }
                let calm = QuotaPetTouchPose.at(reaction, pet: kind, elapsed: 0.5, reduceMotion: true, remaining: 72)
                XCTAssertEqual([calm.dx, calm.dy, calm.rotation, calm.opacity], [0, 0, 0, 1], "\(kind) \(reaction)")
            }
        }
        // Bit puts a tick on its screen; the sausage loses a bite.
        XCTAssertNotEqual(QuotaPetArt.sprite(.bit, size: .widget, mood: .celebrate, remaining: 72, touch: .init(reaction: .cheer, elapsed: 0.5)),
                          QuotaPetArt.sprite(.bit, size: .widget, mood: .celebrate, remaining: 72))
        XCTAssertNotEqual(QuotaPetArt.sprite(.bbq, size: .widget, mood: .celebrate, remaining: 72, touch: .init(reaction: .cheer, elapsed: 1)),
                          QuotaPetArt.sprite(.bbq, size: .widget, mood: .celebrate, remaining: 72))
    }

    func testHolidaysAndHats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        XCTAssertEqual(QuotaPetHoliday.on(day(2026, 10, 31), calendar: calendar), .halloween)
        XCTAssertEqual(QuotaPetHoliday.on(day(2026, 11, 1), calendar: calendar), .halloween)
        XCTAssertNil(QuotaPetHoliday.on(day(2026, 11, 2), calendar: calendar))
        XCTAssertEqual(QuotaPetHoliday.on(day(2026, 12, 25), calendar: calendar), .christmas)
        XCTAssertEqual(QuotaPetHoliday.on(day(2027, 2, 6), calendar: calendar), .springFestival) // New Year's Eve
        XCTAssertEqual(QuotaPetHoliday.on(day(2027, 2, 13), calendar: calendar), .springFestival) // the 7th day
        XCTAssertNil(QuotaPetHoliday.on(day(2027, 2, 14), calendar: calendar))
        XCTAssertEqual(QuotaPetHoliday.on(day(2027, 9, 15), calendar: calendar), .midAutumn)
        XCTAssertEqual(QuotaPetHoliday.on(day(2026, 5, 3), birthday: "05-03", calendar: calendar), .birthday)
        XCTAssertNil(QuotaPetHoliday.on(day(2026, 5, 4), birthday: "05-03", calendar: calendar))

        let dot = UInt8(ascii: ".")
        let hatCodes = Set(QuotaPetHoliday.colors.keys.map { UInt8(ascii: $0.unicodeScalars.first!) })
        for kind in pets {
            let palette = QuotaPetArt.palette(kind, provider: .claude, tint: .original, remaining: 72)
            for holiday in QuotaPetHoliday.allCases {
                let sprite = QuotaPetArt.sprite(kind, size: .widget, mood: .idle, remaining: 72, outfit: holiday)
                XCTAssertTrue(sprite.codes.contains { hatCodes.contains($0) }, "\(kind) \(holiday)")
                for code in sprite.codes where code != dot { XCTAssertNotNil(palette[code], "\(kind) \(holiday)") }
                for particle in holiday.extras(at: 12.3) {
                    XCTAssert(particle.sprite.codes.allSatisfy { $0 == dot || QuotaPetParticle.palette[$0] != nil }, "\(holiday)")
                }
            }
            // The small pet goes without.
            XCTAssertEqual(QuotaPetArt.sprite(kind, size: .minimal, mood: .idle, remaining: 72, outfit: .christmas),
                           QuotaPetArt.sprite(kind, size: .minimal, mood: .idle, remaining: 72))
        }
    }

    func testEveryPetHasItsOwnWords() {
        for kind in pets {
            for moment in QuotaPetVoice.Moment.allCases {
                for chinese in [true, false] {
                    XCTAssertFalse(QuotaPetVoice.line(kind, moment, remaining: 50, chinese: chinese).isEmpty, "\(kind) \(moment)")
                }
            }
        }
        XCTAssertEqual(QuotaPetVoice.line(.bbq, .plenty, remaining: 72, chinese: true), "三分熟")
        XCTAssertEqual(QuotaPetVoice.line(.bbq, .plenty, remaining: 40, chinese: false), "Medium")
        XCTAssertEqual(QuotaPetVoice.line(.ox, .plenty, remaining: 72, chinese: false), "2 boxes on the cart")
        XCTAssertEqual(QuotaPetVoice.line(.pear, .plenty, remaining: 90, chinese: true), "毫无鸭梨")
        XCTAssertEqual(QuotaPetVoice.moment(remaining: 0), .empty)
        XCTAssertEqual(QuotaPetVoice.moment(remaining: 12), .low)
        XCTAssertEqual(QuotaPetVoice.moment(remaining: 50), .plenty)
    }
}
