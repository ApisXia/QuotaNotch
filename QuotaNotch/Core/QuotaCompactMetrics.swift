// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Shared with the original music view: quota content cannot request wider wings.
enum QuotaCompactMetrics {
    static let spacing: CGFloat = 8
    static func iconSize(height: CGFloat) -> CGFloat { max(0, height - 12) }
    static func chinAddition(height: CGFloat) -> CGFloat { 2 * iconSize(height: height) + 20 }
}
