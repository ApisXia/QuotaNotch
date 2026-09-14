// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct QuotaWarningInk {
    let warning: QuotaWarning
    let color: Color
    var track: Color { warning.exhausted ? color.opacity(0.45) : .white.opacity(0.16) }
    var halo: Color { color.opacity(warning.glow) }

    init(accent: Color, percent: Double?, stale: Bool = false) {
        let state = QuotaWarning(percent: percent, stale: stale)
        warning = state
        guard !stale else { color = .gray; return }
        let brand = NSColor(accent).usingColorSpace(.deviceRGB) ?? .white
        func blend(_ base: Double, _ yellow: Double, _ red: Double) -> Double {
            let first = base + (yellow - base) * state.yellow
            return first + (red - first) * state.red
        }
        color = Color(red: blend(Double(brand.redComponent), 0.96, 1.0),
                      green: blend(Double(brand.greenComponent), 0.90, 0.28),
                      blue: blend(Double(brand.blueComponent), 0.27, 0.32))
    }
}
