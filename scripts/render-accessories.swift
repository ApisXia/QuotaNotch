// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

@main
struct RenderAccessories {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        // Exercise the actual shipping Layout with widths unrelated to today's modes.
        for width: CGFloat in [120, 180, 240, 320, 420, 560] {
            for mode in 0..<4 {
                let normal = try render(FixtureNotch(width: width, mode: mode, accessories: 0, clipsCorners: false))
                for count in 1...2 {
                    let expanded = try render(FixtureNotch(width: width, mode: mode, accessories: count, clipsCorners: false))
                    precondition(normal.pixelsWide == expanded.pixelsWide, "Accessory changed primary width")
                    precondition(expanded.pixelsHigh == normal.pixelsHigh + count * 33 * 2, "Unexpected accessory height")
                    // Compare content before clipping: the bottom silhouette intentionally changes.
                    for y in 0..<normal.pixelsHigh { for x in 0..<normal.pixelsWide {
                        precondition(normal.colorAt(x: x, y: y) == expanded.colorAt(x: x, y: y), "Primary content moved")
                    } }
                }
            }
        }
        let sheet = try render(AccessorySheet())
        try sheet.representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: "build/QuotaNotch-dist/Accessory-Layout.png"))
        print("Verified 48 accessory layouts: stable primary pixels and width; 1–2 added rows across 6 widths.")
    }

    @MainActor private static func render<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { fatalError("Native layout render failed") }
        return NSBitmapImageRep(cgImage: cg)
    }
}

private struct FixtureNotch: View {
    let width: CGFloat
    let mode: Int
    let accessories: Int
    var clipsCorners = true

    var body: some View {
        PrimaryNotchLayout {
            HStack {
                if mode == 1 || mode == 2 {
                    RoundedRectangle(cornerRadius: 4).fill(.indigo.gradient)
                        .overlay { Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.white) }
                        .frame(width: 20, height: 20)
                } else if mode == 3 {
                    QuotaBrandMark(brand: .claude).frame(width: 20, height: 20)
                }
                Spacer(minLength: 0)
                if mode >= 2 {
                    CompactQuotaGauge(brand: .claude, percent: 58, showsBrand: mode == 2, size: 20)
                } else if mode == 1 {
                    Image(systemName: "waveform").foregroundStyle(.indigo).frame(width: 20)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: 32)
            ForEach(0..<accessories, id: \.self) { index in
                HStack(spacing: 10) {
                    Image(systemName: index == 0 ? "speaker.wave.2.fill" : "sun.max.fill")
                        .font(.system(size: 12)).frame(width: 20)
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.15))
                            .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: geo.size.width * 0.6) }
                    }.frame(height: 6)
                    Text("60%").font(.system(size: 11)).frame(width: 28)
                }
                .foregroundStyle(.white)
                .frame(height: 15)
                .padding(.horizontal, 12)
                .padding(.top, 8).padding(.bottom, 10)
            }
        }
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: clipsCorners ? 12 : 0, bottomTrailingRadius: clipsCorners ? 12 : 0))
    }
}

private struct AccessorySheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("当前内容保留 · 控制条在下方展开").font(.system(size: 22, weight: .semibold))
            Text("左：正常状态    右：调节音量时").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(0..<4) { mode in
                VStack(alignment: .leading, spacing: 8) {
                    Text(["空闲", "音乐", "音乐 + 额度", "额度"][mode]).font(.system(size: 12))
                    HStack(alignment: .top, spacing: 32) {
                        FixtureNotch(width: 260, mode: mode, accessories: 0)
                        FixtureNotch(width: 260, mode: mode, accessories: 1)
                    }
                }
            }
            Divider()
            Text("扩展验证：主内容变宽、下方增加两行").font(.system(size: 12))
            FixtureNotch(width: 420, mode: 2, accessories: 2)
        }
        .padding(24)
        .background(Color(white: 0.10))
        .foregroundStyle(.white)
    }
}
