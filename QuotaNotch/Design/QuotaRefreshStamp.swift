// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct QuotaRefreshStamp: View {
    let updated: Date?
    let next: Date?
    var error: String?
    var stale = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 5) {
                if error != nil || stale { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                if let updated {
                    Text(QuotaText.localized(error != nil || stale ? "旧数据" : "更新于") + " " + updated.formatted(date: .omitted, time: .shortened))
                } else { Text(LocalizedStringKey(error == nil ? "读取中" : "暂无额度")) }
                if let next, next > context.date {
                    Text("· " + QuotaText.format("%d 秒后可刷新", Int(ceil(next.timeIntervalSince(context.date)))))
                } else { Text("· " + QuotaText.localized("可刷新")) }
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        .help(QuotaText.localized(error ?? "上次成功更新与下次允许查询时间，使用本机时区。"))
    }
}
