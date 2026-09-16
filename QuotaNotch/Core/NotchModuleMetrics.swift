// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Fixed footprints keep the primary widget and secondary state symbol balanced during a swap.
struct NotchModuleMetrics {
    let widgetWidth: CGFloat
    var minimalWidth: CGFloat { widgetWidth > 0 ? 16 : 0 }
    var dividerWidth: CGFloat { widgetWidth > 0 ? 10 : 0 }
    var additionalWidth: CGFloat { minimalWidth + dividerWidth }
    var minimalIconSize: CGFloat { widgetWidth > 0 ? min(14, max(10, widgetWidth * 0.7)) : 0 }
}
