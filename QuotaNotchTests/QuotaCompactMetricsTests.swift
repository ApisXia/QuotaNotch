import XCTest
@testable import QuotaNotchCore

final class QuotaCompactMetricsTests: XCTestCase {
    func testCompactDefaultKeepsOriginalFootprint() {
        for height: CGFloat in [0, 8, 12, 20, 24, 32, 38, 40] {
            for comfortable in [true, false] {
                let size = QuotaCompactMetrics.iconSize(height: height, comfortable: comfortable)
                XCTAssertGreaterThanOrEqual(size, 0)
                XCTAssertLessThanOrEqual(size, height)
                XCTAssertEqual(QuotaCompactMetrics.chinAddition(height: height, comfortable: comfortable), 2 * size + 20)
            }
        }
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32), 20)
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32, comfortable: true), 22)
    }
}
