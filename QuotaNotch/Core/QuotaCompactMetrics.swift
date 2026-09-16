// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum QuotaCompactMetrics {
    static let spacing: CGFloat = 8
    static func iconSize(height: CGFloat, comfortable: Bool = false) -> CGFloat {
        max(0, height - (comfortable ? 10 : 12))
    }
    static func chinAddition(height: CGFloat, comfortable: Bool = false) -> CGFloat {
        2 * iconSize(height: height, comfortable: comfortable) + 20
    }
}
