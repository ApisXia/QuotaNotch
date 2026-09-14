// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct QuotaRefreshStamp: View {
    let updated: Date?
    let next: Date?
    var error: String?

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 4) {
            if error != nil { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            if let updated {
                Text(QuotaText.localized(error == nil ? "更新于" : "旧数据") + " " + clock(updated))
            } else { Text(LocalizedStringKey(error == nil ? "读取中" : "暂无额度")) }
            if let next { Text("· " + QuotaText.localized("下次") + " " + clock(next)) }
        }
        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        .help(QuotaText.localized(error ?? "上次成功更新与下次允许查询时间，使用本机时区。"))
    }
}
