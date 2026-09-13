// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct QuotaWindowTile: View {
    let title: String
    let percent: Double
    let reset: Date?
    let accent: Color
    var stale = false
    var pinned = false
    var onPin: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button(action: onPin) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(pinned ? accent : .gray)
                }
                .buttonStyle(.plain)
                .help(QuotaText.localized(pinned ? "取消固定" : "固定此额度"))
                .accessibilityLabel(QuotaText.localized(pinned ? "取消固定" : "固定此额度") + " " + title)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(percent, specifier: "%.0f")%")
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(stale ? .gray : .white)
                Text(LocalizedStringKey(stale ? "剩余 · 旧数据" : "剩余"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.09))
                    .overlay(alignment: .leading) {
                        Capsule().fill(stale ? .gray : accent)
                            .frame(width: proxy.size.width * max(0, min(1, percent / 100)))
                    }
            }.frame(height: 3)
            HStack(spacing: 3) {
                if let reset {
                    Text("重置")
                    Text(reset, style: .date)
                    Text(reset, style: .time)
                } else { Text("重置时间未知") }
            }
            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct QuotaProviderTab: View {
    let title: String
    let brand: QuotaBrand
    let selected: Bool
    var onSelect: () -> Void = {}
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                QuotaBrandMark(brand: brand).frame(width: 13, height: 13)
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .medium))
            }
            .padding(.horizontal, 11).padding(.vertical, 3)
            .foregroundStyle(selected ? .white : .gray)
            .background(selected ? .white.opacity(0.13) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
