// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// One widget occupies its icon plus the existing 8-point camera gap and 14-point outer inset.
/// An additional minimal, including its divider, can add at most one third of that footprint.
struct NotchModuleMetrics {
    let widgetWidth: CGFloat
    var widgetFootprint: CGFloat { widgetWidth > 0 ? widgetWidth + 22 : 0 }
    var additionalWidth: CGFloat { floor(widgetFootprint / 3) }
    var dividerWidth: CGFloat { min(3, additionalWidth) }
    var minimalWidth: CGFloat { max(0, additionalWidth - dividerWidth) }
}
