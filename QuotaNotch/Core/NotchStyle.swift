// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Product defaults, intentionally not user preferences.
enum NotchStyle {
    static let scalesCorners = true
    static let castsShadow = true
    static let coloredSpectrogram = true
    static let albumGlow = true
    static let playerTinting = true
    static let hoverDelay: TimeInterval = 0.3
}

enum NotchScreenSizing {
    static func height(safeArea: Double, menuBar: Double) -> Double {
        if safeArea.isFinite && safeArea > 0 { return safeArea }
        if menuBar.isFinite && menuBar > 0 { return menuBar }
        // Auto-hidden menu bars still need a compact, usable non-notch indicator.
        return 24
    }
}
