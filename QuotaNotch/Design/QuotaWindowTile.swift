// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Bars are neutral while quota is healthy and only take on warning colours when it runs low,
/// so a brand colour (Claude's orange) is never mistaken for a warning.
let quotaNeutralBar = Color(white: 0.86)

struct QuotaWindowTile: View {
    /// The panel scales as a whole now (Settings → Size), so text keeps its base size.
    private let comfortable = false
    let title: String
    let percent: Double
    let reset: Date?
    let accent: Color
    var stale = false
    var pinned = false
    /// Shown before the title in the compact two-provider layout.
    var brand: QuotaBrand? = nil
    /// One line for name and reset time, so two providers fit in the open notch.
    var compact = false
    var onPin: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = QuotaWarningInk(accent: accent, percent: percent, stale: stale)
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            HStack(spacing: 5) {
                if let brand { QuotaBrandMark(brand: brand, muted: stale).frame(width: 11, height: 11) }
                Text(title).font(.system(size: comfortable ? 11 : 10, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if compact { resetText.layoutPriority(-1) }
                pinButton
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(QuotaText.percent(percent) + "%")
                    .font(.system(size: compact ? (comfortable ? 20 : 18) : (comfortable ? 24 : 22), weight: .semibold, design: .rounded))
                    .monospacedDigit()
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
            if !compact { resetText }
        }
        .padding(.horizontal, 10).padding(.vertical, compact ? 5 : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var resetText: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let reset {
                Text(QuotaText.countdown(reset, now: context.date))
                    .help(reset.formatted(date: .complete, time: .shortened))
            } else { Text("重置时间未知") }
        }
        .font(.system(size: comfortable ? 11 : 10)).foregroundStyle(.secondary).lineLimit(1)
    }

    private var pinButton: some View {
        Button(action: onPin) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 11))
                .foregroundStyle(pinned ? accent : .gray)
        }
        .buttonStyle(.plain)
        .help(QuotaText.localized(pinned ? "不再在刘海中显示" : "收起时在刘海中显示"))
        .accessibilityLabel(QuotaText.localized(pinned ? "不再在刘海中显示" : "收起时在刘海中显示") + " " + title)
    }
}

struct QuotaProviderTab: View {
    /// The panel scales as a whole now (Settings → Size), so text keeps its base size.
    private let comfortable = false
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
