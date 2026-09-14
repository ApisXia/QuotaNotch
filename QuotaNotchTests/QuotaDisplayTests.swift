import XCTest
@testable import QuotaNotchCore

final class QuotaDisplayTests: XCTestCase {
    func testExistingSettingsKeepNumbersOff() throws {
        for text in ["{}", #"{"selected":null}"#, #"{"left":{"providerID":"claude","windowID":"five_hour"}}"#] {
            let pins = try JSONDecoder().decode(QuotaPins.self, from: Data(text.utf8))
            XCTAssertFalse(pins.showsNumbers)
        }
    }

    func testNumberPreferencePersistsWithoutChangingPinnedWindow() throws {
        let pin = QuotaPin(providerID: "codex", windowID: "primary_window")
        for enabled in [true, false] {
            let pins = QuotaPins(selected: pin, showsNumbers: enabled)
            let restored = try JSONDecoder().decode(QuotaPins.self, from: JSONEncoder().encode(pins))
            XCTAssertEqual(restored, pins)
        }
    }

    func testAllWindowsReachableInPagesOfAtMostTwo() {
        for total in 0...9 {
            let indices = (0..<QuotaWindowPages.count(windows: total)).flatMap { page -> [Int] in
                let range = QuotaWindowPages.range(windows: total, page: page)
                XCTAssertLessThanOrEqual(range.count, 2)
                return Array(range)
            }
            XCTAssertEqual(indices, Array(0..<total))
        }
        XCTAssertEqual(QuotaWindowPages.count(windows: 2), 1)
    }

    func testPageIsClampedAfterWindowCountShrinks() {
        XCTAssertEqual(QuotaWindowPages.range(windows: 2, page: 4), 0..<2)
        XCTAssertEqual(QuotaWindowPages.range(windows: 3, page: -1), 0..<2)
        XCTAssertEqual(QuotaWindowPages.range(windows: 0, page: 1), 0..<0)
    }
}
