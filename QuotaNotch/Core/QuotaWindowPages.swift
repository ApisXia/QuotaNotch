// SPDX-License-Identifier: GPL-3.0-only
enum QuotaWindowPages {
    static func count(windows: Int) -> Int { max(1, (max(0, windows) + 1) / 2) }
    static func range(windows: Int, page: Int) -> Range<Int> {
        let total = max(0, windows)
        let index = min(max(0, page), count(windows: total) - 1)
        let start = index * 2
        return start..<min(start + 2, total)
    }
}
