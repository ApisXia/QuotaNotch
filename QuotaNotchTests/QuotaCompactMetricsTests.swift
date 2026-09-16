import XCTest
@testable import QuotaNotchCore

final class QuotaCompactMetricsTests: XCTestCase {
    func testEnlargedDefaultAndCompactAlternativeFitNotchHeight() {
        for height: CGFloat in [0, 8, 12, 20, 24, 32, 38, 40] {
            for comfortable in [true, false] {
                let size = QuotaCompactMetrics.iconSize(height: height, comfortable: comfortable)
                XCTAssertGreaterThanOrEqual(size, 0)
                XCTAssertLessThanOrEqual(size, height)
                XCTAssertEqual(QuotaCompactMetrics.chinAddition(height: height, comfortable: comfortable), 2 * size + 20)
            }
        }
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32), 28)
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32, comfortable: false), 24)
    }
}
