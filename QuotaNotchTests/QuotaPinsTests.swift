import XCTest
@testable import QuotaNotchCore

final class QuotaPinsTests: XCTestCase {
    private let claude = QuotaPin(providerID: "claude", windowID: "five_hour")
    private let codex = QuotaPin(providerID: "codex", windowID: "secondary_window")

    func testFourTaskCombinations() {
        let scenarios: [(QuotaPin?, Bool, QuotaPresentation)] = [
            (nil, false, .none), (nil, true, .music),
            (claude, false, .quota), (claude, true, .combined)
        ]
        for (pin, music, expected) in scenarios {
            let pins = QuotaPins(selected: pin)
            XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: false, musicPlaying: music), expected)
        }
    }

    func testPausingMusicKeepsQuotaAndResumingRestoresCombined() {
        let pins = QuotaPins(selected: codex)
        for (playing, expected) in [(true, QuotaPresentation.combined), (false, .quota), (true, .combined)] {
            XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: false, musicPlaying: playing), expected)
        }
        XCTAssertEqual(pins.selected, codex)
    }

    func testDisablingQuotaPreservesMusicAndChoice() {
        let pins = QuotaPins(selected: claude)
        XCTAssertEqual(pins.presentation(enabled: false, hidden: false, replacingPrimary: false, musicPlaying: true), .music)
        XCTAssertEqual(pins.presentation(enabled: false, hidden: false, replacingPrimary: false, musicPlaying: false), .none)
        XCTAssertEqual(pins.selected, claude)
    }

    func testReplacementAndHiddenStatesSuppressBothTasks() {
        let pins = QuotaPins(selected: codex)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: true, musicPlaying: true), .none)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: true, replacingPrimary: false, musicPlaying: true), .none)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: false, musicPlaying: true), .combined)
    }

    func testSelectionReplacementAndClearingPersist() throws {
        var pins = QuotaPins(selected: claude)
        pins.selected = codex
        XCTAssertEqual(try JSONDecoder().decode(QuotaPins.self, from: JSONEncoder().encode(pins)).selected, codex)
        pins.selected = nil
        XCTAssertNil(try JSONDecoder().decode(QuotaPins.self, from: JSONEncoder().encode(pins)).selected)
    }

    func testLegacyTwoSidedSettingsPreferRightRegardlessOfMusicPreference() throws {
        let data = Data(#"{"left":{"providerID":"claude","windowID":"five_hour"},"right":{"providerID":"codex","windowID":"secondary_window"},"yieldToMusic":true}"#.utf8)
        let pins = try JSONDecoder().decode(QuotaPins.self, from: data)
        XCTAssertEqual(pins.selected, codex)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: false, musicPlaying: true), .combined)
    }

    func testLegacyLeftOnlyAndInvalidRightFallback() throws {
        for right in ["null", #"{"providerID":"unsupported","windowID":"unknown"}"#] {
            let data = Data("{\"left\":{\"providerID\":\"claude\",\"windowID\":\"five_hour\"},\"right\":\(right)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(QuotaPins.self, from: data).selected, claude)
        }
    }

    func testUnknownProviderDoesNotClaimQuotaSpace() throws {
        let data = Data(#"{"selected":{"providerID":"unsupported","windowID":"unknown"}}"#.utf8)
        let pins = try JSONDecoder().decode(QuotaPins.self, from: data)
        XCTAssertFalse(pins.hasPins)
        XCTAssertEqual(pins.presentation(enabled: true, hidden: false, replacingPrimary: false, musicPlaying: true), .music)
    }
}
