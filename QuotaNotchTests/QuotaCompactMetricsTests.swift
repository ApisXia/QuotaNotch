import XCTest
@testable import QuotaNotchCore

final class QuotaCompactMetricsTests: XCTestCase {
    func testQuotaUsesOriginalMusicFootprintForEveryHeight() {
        let heights: [CGFloat] = [0, 8, 12, 20, 24, 32, 38, 40]
        for height in heights {
            let originalIcon = max(0, height - 12)
            XCTAssertEqual(QuotaCompactMetrics.iconSize(height: height), originalIcon)
            XCTAssertEqual(QuotaCompactMetrics.chinAddition(height: height), 2 * originalIcon + 20)
        }
        XCTAssertEqual(QuotaCompactMetrics.spacing, 8)
    }

    func testCommonNotchDoesNotReserveTextSizedWings() {
        XCTAssertEqual(QuotaCompactMetrics.iconSize(height: 32), 20)
        XCTAssertEqual(QuotaCompactMetrics.chinAddition(height: 32), 60)
    }
}
