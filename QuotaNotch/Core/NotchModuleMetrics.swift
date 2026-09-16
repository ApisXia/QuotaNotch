// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Shared geometry keeps token/task swaps stable while giving three digits room to breathe.
struct NotchModuleMetrics {
    let widgetWidth: CGFloat
    var minimalWidth: CGFloat { widgetWidth > 0 ? 16 : 0 }
    var dividerWidth: CGFloat { widgetWidth > 0 ? 4 : 0 }
    var additionalWidth: CGFloat { minimalWidth + dividerWidth }
    var minimalContentHeight: CGFloat { max(18, min(22, widgetWidth)) }
    var minimalNumberHeight: CGFloat { 9 }
    var minimalSpacing: CGFloat { 1 }
    var minimalIconRowHeight: CGFloat { minimalContentHeight - minimalNumberHeight - minimalSpacing }
    var minimalIconSize: CGFloat { min(10, minimalIconRowHeight) }
}
