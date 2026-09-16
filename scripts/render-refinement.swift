// Compare original and shipping components at identical point sizes.
import SwiftUI
import AppKit

@main
struct RenderRefinement {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        UserDefaults.standard.set(false, forKey: "quotaComfortable")
        let renderer = ImageRenderer(content: Comparison().preferredColorScheme(.dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("Rendering failed") }
        try data.write(to: URL(fileURLWithPath: "build/QuotaNotch-dist/Refinement-Comparison.png"))
    }
}

private struct Comparison: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("QuotaNotch · proportion study").font(.system(size: 20, weight: .semibold))
            Text("Identical scale · 20pt icons · original panel footprint · sample data").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                column(legacy: true)
                column(legacy: false)
            }
        }
        .padding(24).foregroundStyle(.white).background(Color(white: 0.08))
    }
    private func column(legacy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(legacy ? "Original" : "Refined").font(.system(size: 15, weight: .semibold))
            Text("Closed").font(.system(size: 11)).foregroundStyle(.secondary)
            CompactComparison(legacy: legacy, music: false)
            Text("Music + quota").font(.system(size: 11)).foregroundStyle(.secondary)
            CompactComparison(legacy: legacy, music: true)
            Text("Expanded").font(.system(size: 11)).foregroundStyle(.secondary)
            PanelComparison(legacy: legacy)
            Text(legacy ? "Original ring inset and 21pt percentage" : "Corrected ring inset and 22pt percentage; no larger panel")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(width: 600, alignment: .leading)
    }
}

private struct CompactComparison: View {
    let legacy: Bool
    let music: Bool
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if music {
                    RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [.indigo, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else { QuotaBrandMark(brand: .claude) }
            }.frame(width: 20, height: 20)
            Color.clear.frame(width: 179, height: 32)
            Group {
                if legacy { OriginalCompactQuotaGauge(brand: .claude, percent: 58, showsBrand: music, showsNumbers: true, size: 20) }
                else { CompactQuotaGauge(brand: .claude, percent: 58, showsBrand: music, showsNumbers: true, size: 20) }
            }.frame(width: 20, height: 20)
        }
        .padding(.horizontal, 14).frame(height: 32)
        .background(.black, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PanelComparison: View {
    let legacy: Bool
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                if legacy {
                    OriginalQuotaProviderTab(title: "Claude", brand: .claude, selected: true)
                    OriginalQuotaProviderTab(title: "Codex", brand: .codex, selected: false)
                } else {
                    QuotaProviderTab(title: "Claude", brand: .claude, selected: true)
                    QuotaProviderTab(title: "Codex", brand: .codex, selected: false)
                }
                Spacer(minLength: 0)
            }.padding(2).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 8) {
                if legacy {
                    OriginalQuotaWindowTile(title: "5 hours", percent: 58, reset: nil, accent: QuotaBrand.claude.color, pinned: true)
                    OriginalQuotaWindowTile(title: "7 days", percent: 25, reset: nil, accent: QuotaBrand.claude.color)
                } else {
                    QuotaWindowTile(title: "5 hours", percent: 58, reset: nil, accent: QuotaBrand.claude.color, pinned: true)
                    QuotaWindowTile(title: "7 days", percent: 25, reset: nil, accent: QuotaBrand.claude.color)
                }
            }
            HStack(spacing: 10) {
                Label("Claude · 5 hours", systemImage: "pin.fill").lineLimit(1)
                Spacer(minLength: 0)
                Text(legacy ? "Updated 15:33 · Next 15:48" : "Refresh in 2:00").font(.system(size: 9)).foregroundStyle(.secondary)
                Image(systemName: "gearshape")
                Label("Refresh", systemImage: "arrow.clockwise").fixedSize()
                Label("Pause", systemImage: "pause").fixedSize()
            }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(width: 584, height: 126)
        .padding(8).background(.black, in: RoundedRectangle(cornerRadius: 16))
    }
}
