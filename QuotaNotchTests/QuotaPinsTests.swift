import XCTest
@testable import QuotaNotchCore

final class QuotaPinsTests: XCTestCase {
    private let claude = QuotaPin(providerID: "claude", windowID: "five_hour")
    private let codex = QuotaPin(providerID: "codex", windowID: "secondary_window")

    func testMovingAndReplacingOnlyAffectsAssignedSlots() {
        var pins = QuotaPins()
        pins.assign(claude, toLeft: true)
        pins.assign(codex, toLeft: false)
        pins.assign(claude, toLeft: false)
        XCTAssertNil(pins.left)
        XCTAssertEqual(pins.right, claude)
        pins.assign(codex, toLeft: true)
        pins.remove(claude)
        XCTAssertEqual(pins.left, codex)
        XCTAssertNil(pins.right)
    }

    func testMusicYieldsThenRestoresPinsWithoutChangingSelection() {
        var pins = QuotaPins()
        pins.assign(claude, toLeft: true)
        XCTAssertFalse(pins.shouldDisplay(enabled: true, hidden: false, transient: false, musicPlaying: true))
        XCTAssertTrue(pins.shouldDisplay(enabled: true, hidden: false, transient: false, musicPlaying: false))
        pins.yieldToMusic = false
        XCTAssertTrue(pins.shouldDisplay(enabled: true, hidden: false, transient: false, musicPlaying: true))
        XCTAssertEqual(pins.left, claude)
    }

    func testTransientSystemEventsAndHiddenNotchAlwaysWin() {
        var pins = QuotaPins()
        pins.assign(codex, toLeft: false)
        pins.yieldToMusic = false
        XCTAssertFalse(pins.shouldDisplay(enabled: true, hidden: false, transient: true, musicPlaying: false))
        XCTAssertFalse(pins.shouldDisplay(enabled: true, hidden: true, transient: false, musicPlaying: false))
        XCTAssertFalse(pins.shouldDisplay(enabled: false, hidden: false, transient: false, musicPlaying: false))
    }

    func testNoSelectionOrUnknownProviderDoesNotCreateWings() {
        var pins = QuotaPins()
        XCTAssertFalse(pins.shouldDisplay(enabled: true, hidden: false, transient: false, musicPlaying: false))
        pins.left = QuotaPin(providerID: "unsupported", windowID: "unknown")
        XCTAssertFalse(pins.hasPins)
    }

    func testPinsAndMusicPreferenceSurviveRestart() throws {
        var pins = QuotaPins()
        pins.assign(codex, toLeft: false)
        pins.yieldToMusic = false
        let restored = try JSONDecoder().decode(QuotaPins.self, from: JSONEncoder().encode(pins))
        XCTAssertEqual(restored, pins)
    }
}
