// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Continuous remaining-quota bands shared by every ring and horizontal bar.
struct QuotaWarning: Equatable {
    let fraction: Double
    let yellow: Double
    let red: Double
    let glow: Double
    let exhausted: Bool

    init(percent: Double?, stale: Bool = false) {
        let valid = percent?.isFinite == true
        let p = valid ? min(100, max(0, percent!)) : 100
        fraction = valid ? p / 100 : 0
        yellow = valid && !stale ? min(1, max(0, (45 - p) / 10)) : 0
        red = valid && !stale ? min(1, max(0, (15 - p) / 10)) : 0
        glow = 0.30 * yellow + 0.20 * red
        exhausted = valid && !stale && p == 0
    }
}
