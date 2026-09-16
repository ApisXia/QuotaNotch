// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum QuotaCompactMetrics {
    static let spacing: CGFloat = 8
    static func iconSize(height: CGFloat, comfortable: Bool = true) -> CGFloat {
        max(0, height - (comfortable ? 4 : 8))
    }
    static func chinAddition(height: CGFloat, comfortable: Bool = true) -> CGFloat {
        2 * iconSize(height: height, comfortable: comfortable) + 20
    }
}
