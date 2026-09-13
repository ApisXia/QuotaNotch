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
        XCTAssertNil(defaults.object(forKey: "AppleLanguages"))
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
