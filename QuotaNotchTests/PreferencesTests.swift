import XCTest
@testable import QuotaNotchCore

final class PreferencesTests: XCTestCase {
    func testPausedProvidersAreAbsent() {
        XCTAssertEqual(QuotaProviderVisibility.visible(disabled: ["gemini"]), [.claude, .codex])
    }
    func testPausingCurrentProviderSelectsNextVisibleProvider() {
        XCTAssertEqual(QuotaProviderVisibility.selection(.claude, disabled: ["claude"]), .codex)
        XCTAssertEqual(QuotaProviderVisibility.selection(.codex, disabled: ["gemini"]), .codex)
    }
    func testAllPausedHasNoSelection() {
        let disabled = Set(QuotaProvider.allCases.map(\.rawValue))
        XCTAssertTrue(QuotaProviderVisibility.visible(disabled: disabled).isEmpty)
        XCTAssertNil(QuotaProviderVisibility.selection(.claude, disabled: disabled))
    }
    func testLanguageOverridePersistsAndSystemClearsOnlyOverride() throws {
        let name = "QuotaNotchTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("existing-pin", forKey: "quotaNotchPins")
        QuotaLanguage.chinese.save(in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
        XCTAssertEqual(QuotaLanguage.stored(in: defaults), .chinese)
        QuotaLanguage.english.save(in: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        QuotaLanguage.system.save(in: defaults)
        // Removing an app override reveals the system language through defaults lookup.
        XCTAssertNil(defaults.persistentDomain(forName: name)?["AppleLanguages"])
        XCTAssertEqual(QuotaLanguage.stored(in: defaults), .system)
        XCTAssertEqual(defaults.string(forKey: "quotaNotchPins"), "existing-pin")
    }
    func testInvalidSavedLanguageFallsBackToSystem() throws {
        let name = "QuotaNotchTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("invalid", forKey: "quotaNotchLanguage")
        XCTAssertEqual(QuotaLanguage.stored(in: defaults), .system)
    }
}

final class SettingsSelectionTests: XCTestCase {
    func testClickFillsAnEmptySlotWithoutChangingExistingControls() {
        XCTAssertEqual(SettingsSelection.inserting("volume", into: ["previous", "play", ""], empty: ""), ["previous", "play", "volume"])
    }
    func testFullLayoutRequiresAnExplicitReplacement() {
        let slots = ["previous", "play", "next"]
        XCTAssertNil(SettingsSelection.inserting("volume", into: slots, empty: ""))
        XCTAssertEqual(SettingsSelection.inserting("volume", into: slots, empty: "", destination: 1), ["previous", "volume", "next"])
    }
    func testClickingAnExistingControlDoesNotDuplicateIt() {
        XCTAssertEqual(SettingsSelection.inserting("play", into: ["", "play", "next"], empty: ""), ["", "play", "next"])
        XCTAssertEqual(SettingsSelection.inserting("play", into: ["play", "play", "next"], empty: ""), ["play", "", "next"])
    }
    func testDropMovesExistingControlAndClearsLegacyDuplicates() {
        XCTAssertEqual(SettingsSelection.inserting("play", into: ["play", "play", "next"], empty: "", destination: 2), ["", "", "play"])
        XCTAssertNil(SettingsSelection.inserting("play", into: ["play"], empty: "", destination: 5))
    }
    func testSavedCandidatesRemainEditableWithoutResults() {
        let pin = QuotaPin(providerID: "claude", windowID: "five_hour")
        var pins = QuotaPins()
        pins.candidates = [pin]
        XCTAssertEqual(pins.editableCandidates(available: []), [pin])
        XCTAssertEqual(pins.editableCandidates(available: [pin]), [pin])
    }
    func testSavedUnavailableCandidatesAppearAlongsideAvailableWindows() {
        let old = QuotaPin(providerID: "claude", windowID: "seven_day")
        let new = QuotaPin(providerID: "codex", windowID: "primary_window")
        var pins = QuotaPins()
        pins.candidates = [old]
        XCTAssertEqual(pins.editableCandidates(available: [new, new]), [new, old])
    }
}

final class NotchScreenSizingTests: XCTestCase {
    func testHardwareNotchDeterminesHeight() {
        XCTAssertEqual(NotchScreenSizing.height(safeArea: 38, menuBar: 44), 38)
    }
    func testExternalDisplayFollowsMenuBar() {
        XCTAssertEqual(NotchScreenSizing.height(safeArea: 0, menuBar: 24), 24)
        XCTAssertEqual(NotchScreenSizing.height(safeArea: 0, menuBar: 32), 32)
    }
    func testHiddenMenuBarHasUsableFallback() {
        XCTAssertEqual(NotchScreenSizing.height(safeArea: 0, menuBar: 0), 24)
        XCTAssertEqual(NotchScreenSizing.height(safeArea: .nan, menuBar: -.infinity), 24)
    }
}
