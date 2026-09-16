// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct QuotaWindowTile: View {
    @AppStorage("quotaComfortable") private var comfortable = false
    let title: String
    let percent: Double
    let reset: Date?
    let accent: Color
    var stale = false
    var pinned = false
    var onPin: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = QuotaWarningInk(accent: accent, percent: percent, stale: stale)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: comfortable ? 11 : 10, weight: .medium))
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
                Text(QuotaText.percent(percent) + "%")
                    .font(.system(size: comfortable ? 24 : 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(stale ? .gray : .white)
                Text(LocalizedStringKey(stale ? "剩余 · 旧数据" : "剩余"))
                    .font(.system(size: comfortable ? 11 : 10)).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule().fill(ink.track)
                    .shadow(color: ink.warning.exhausted ? ink.halo : .clear, radius: 1.5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(ink.color)
                            .frame(width: proxy.size.width * ink.warning.fraction)
                            .shadow(color: ink.halo, radius: 1.5)
                    }
            }.frame(height: 3)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: percent)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let reset {
                    Text(QuotaText.countdown(reset, now: context.date))
                        .help(reset.formatted(date: .complete, time: .shortened))
                } else { Text("重置时间未知") }
            }
            .font(.system(size: comfortable ? 11 : 10)).foregroundStyle(.secondary).lineLimit(1)

        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct QuotaProviderTab: View {
    @AppStorage("quotaComfortable") private var comfortable = false
    let title: String
    let brand: QuotaBrand
    let selected: Bool
    var onSelect: () -> Void = {}
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                QuotaBrandMark(brand: brand).frame(width: 13, height: 13)
                Text(title).font(.system(size: comfortable ? 12 : 11, weight: selected ? .semibold : .medium))
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
