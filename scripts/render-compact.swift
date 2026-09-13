// SPDX-License-Identifier: GPL-3.0-only
// Native SwiftUI fixture sheet. Shares the shipping vector marks and gauge code.
import SwiftUI
import AppKit

@main
struct RenderCompact {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: FixtureSheet().preferredColorScheme(.dark))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Could not render native SwiftUI fixture sheet")
        }
        try png.write(to: URL(fileURLWithPath: "build/QuotaNotch-dist/Compact-UX.png"))
    }
}

private struct FixtureSheet: View {
    private let height: CGFloat = 32
    private var size: CGFloat { QuotaCompactMetrics.iconSize(height: height) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("QuotaNotch · compact wings").font(.system(size: 22, weight: .semibold))
            Text("Native SwiftUI fixtures — no live accounts. 32pt notch / 20pt icon.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Each row below is 263pt wide, matching the original music layout.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            row("Music reference", brand: nil, percent: nil, music: true)
            row("Claude · 58%", brand: .claude, percent: 58)
            row("Music + Claude", brand: .claude, percent: 58, music: true)
            row("Codex · 73%", brand: .codex, percent: 73)
            row("Music + Codex", brand: .codex, percent: 73, music: true)
            row("Empty · 0%", brand: .claude, percent: 0)
            row("Full · 100%", brand: .codex, percent: 100)
            row("Unknown", brand: .codex, percent: nil, music: true)
            row("Stale · 9%", brand: .claude, percent: 9, music: true, stale: true)
            row("Numbers · 58", brand: .claude, percent: 58, music: true, numbers: true)
            row("Numbers · 100", brand: .codex, percent: 100, music: true, numbers: true)
            row("Numbers · 0", brand: .codex, percent: 0, numbers: true)
            row("Old number · 9", brand: .claude, percent: 9, music: true, stale: true, numbers: true)
            HStack(spacing: 10) {
                Label("Claude · 5 小时", systemImage: "pin.fill")
                Spacer()
                QuotaRefreshStamp(updated: Date(timeIntervalSince1970: 1789400000),
                                  next: Date(timeIntervalSince1970: 1789400900))
                Image(systemName: "gearshape")
                Label("刷新", systemImage: "arrow.clockwise")
                Label("暂停", systemImage: "pause")
            }
            .font(.system(size: 11)).padding(10)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            Divider()
            Text("4× detail — badge remains inside the 20pt box").font(.system(size: 12))
            HStack(spacing: 70) {
                QuotaBrandMark(brand: .claude).frame(width: size, height: size).scaleEffect(4)
                QuotaBrandMark(brand: .codex).frame(width: size, height: size).scaleEffect(4)
                CompactQuotaGauge(brand: .claude, percent: 58, showsBrand: true, showsNumbers: true, size: size).scaleEffect(4)
                CompactQuotaGauge(brand: .codex, percent: 100, showsBrand: true, showsNumbers: true, size: size).scaleEffect(4)
            }
            .padding(.horizontal, 30).frame(height: 86)
            Text("Album artwork and bars are placeholders. Real notch positioning / animation needs Mac testing.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 620)
        .foregroundStyle(.white)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
    }

    private var album: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [.indigo, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }

    private var bars: some View {
        HStack(spacing: 2) {
            ForEach([5.0, 10.0, 7.0, 12.0], id: \.self) { h in
                Capsule().fill(.white).frame(width: 2, height: h)
            }
        }
    }

    private func row(_ label: String, brand: QuotaBrand?, percent: Double?, music: Bool = false, stale: Bool = false, numbers: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).frame(width: 160, alignment: .leading)
            HStack(spacing: QuotaCompactMetrics.spacing) {
                Group {
                    if music {
                        album.overlay(alignment: .bottomTrailing) {
                            if brand != nil {
                                bars.scaleEffect(0.45).frame(width: 9, height: 7).padding(1)
                                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    } else if let brand { QuotaBrandMark(brand: brand) }
                }
                .frame(width: size, height: size).clipped()
                Color.black.frame(width: 185 - 6, height: height)
                Group {
                    if let brand {
                        CompactQuotaGauge(brand: brand, percent: percent, stale: stale, showsBrand: music, showsNumbers: numbers, size: size)
                    } else { bars }
                }
                .frame(width: size, height: size).clipped()
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(.black, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
