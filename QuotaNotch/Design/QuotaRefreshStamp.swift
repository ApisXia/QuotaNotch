// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct QuotaRefreshStamp: View {
    let updated: Date?
    let next: Date?
    var error: String?
    var stale = false
    var refreshing = false

    private var detail: String {
        var lines: [String] = []
        if let updated { lines.append(QuotaText.localized("更新于") + " " + updated.formatted(date: .abbreviated, time: .standard)) }
        if let next { lines.append(QuotaText.localized("下次") + " " + next.formatted(date: .abbreviated, time: .standard)) }
        if let error { lines.append(QuotaText.localized(error)) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                if error != nil || stale { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                if refreshing {
                    Text("正在刷新…")
                } else if error != nil || stale {
                    Text(LocalizedStringKey(updated == nil ? "暂无额度" : "旧数据"))
                } else if let next, next > context.date {
                    let seconds = max(0, Int(ceil(next.timeIntervalSince(context.date))))
                    Text(QuotaText.format("%@ 后可刷新", String(format: "%d:%02d", seconds / 60, seconds % 60)))
                        .monospacedDigit()
                } else if let updated {
                    Text(QuotaText.localized("更新于") + " " + updated.formatted(date: .omitted, time: .shortened))
                } else { Text("读取中") }
            }
        }
        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        .help(detail)
    }
}
