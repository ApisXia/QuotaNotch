// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaPetKind {
    /// "麻薯 · 猫" / "Mochi · Cat"
    var displayName: String {
        let t = AgentText.t
        switch self {
        case .mochi: return t("麻薯 · 猫", "Mochi · Cat")
        case .bit: return t("比特 · 机器人", "Bit · Robot")
        case .jelly: return t("果冻 · 史莱姆", "Jelly · Slime")
        case .ghost: return t("飘飘 · 小幽灵", "Wisp · Ghost")
        case .sprout: return t("苗苗 · 豆芽", "Sprout · Seedling")
        case .fish: return t("摸鱼 · 鱼缸", "Slacker · Fishbowl")
        case .pear: return t("鸭梨 · 压力山大", "Duck Pear · Under Pressure")
        case .bbq: return t("芭比Q了 · 烤肠", "BBQ'd · Sausage")
        case .ox: return t("牛马 · 打工牛", "Workhorse · Cow")
        }
    }

    /// How the pet shows quota, in a few words.
    var gaugeLine: String {
        let t = AgentText.t
        switch self {
        case .mochi: return t("那杯茶就是额度", "The tea is your quota")
        case .bit: return t("肚子上的电量条", "The battery on its belly")
        case .jelly: return t("身体里的水", "The water inside it")
        case .ghost: return t("越用越透明", "Fades as you use quota")
        case .sprout: return t("盆里的水，叶子会耷拉", "Pot water; leaves droop")
        case .fish: return t("缸里的水", "The water in the bowl")
        case .pear: return t("额度越少，头上的山越大", "Less quota, bigger mountain")
        case .bbq: return t("额度越少，烤得越焦", "Less quota, more burnt")
        case .ox: return t("车上的箱子越堆越多", "More boxes as you use it")
        }
    }
}

/// Settings › Pet: one small moving card per pet. Clicking a card picks it, and it celebrates.
struct QuotaPetPicker: View {
    @Binding var selection: QuotaPetKind
    let provider: QuotaProvider
    @State private var cheering: QuotaPetKind?
    @State private var cheerStart = Date.distantPast

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(QuotaPetKind.pets.enumerated()), id: \.element) { index, kind in
                Button {
                    selection = kind
                    cheering = kind
                    cheerStart = Date()
                } label: {
                    card(kind, index: index)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.displayName)
                .accessibilityAddTraits(kind == selection ? .isSelected : [])
            }
        }
        .task(id: cheerStart) {
            guard cheering != nil else { return }
            let start = cheerStart
            try? await Task.sleep(for: .seconds(QuotaPetReaction.cheer.duration))
            if cheerStart == start { cheering = nil }
        }
    }

    private func card(_ kind: QuotaPetKind, index: Int) -> some View {
        let selected = kind == selection
        return HStack(spacing: 8) {
            preview(kind, index: index)
                .frame(width: 60, height: 50)
                .background(.black, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(kind.gaugeLine).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Color.accentColor).padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    /// The pet resting with quota to spare; it makes its idle move now and then, and celebrates
    /// right after it's picked.
    @ViewBuilder private func preview(_ kind: QuotaPetKind, index: Int) -> some View {
        if cheering == kind {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let e = context.date.timeIntervalSince(cheerStart)
                pet(kind, index: index, touch: e < QuotaPetReaction.cheer.duration ? .init(reaction: .cheer, elapsed: e) : nil)
            }
        } else {
            pet(kind, index: index, touch: nil)
        }
    }

    private func pet(_ kind: QuotaPetKind, index: Int, touch: QuotaPetTouchMoment?) -> some View {
        QuotaPetView(kind: kind, size: .widget, provider: provider,
                     window: QuotaWindow(id: "preview", title: "", remainingPercent: 72, resetsAt: nil),
                     stale: false, scale: 2, fixedMood: .idle, touch: touch, idleOffset: Double(index) * 5)
    }
}

/// A pet's picture for menus: the 20 × 16 sprite at one point per pixel.
@MainActor
enum QuotaPetIcon {
    private static var cache: [QuotaPetKind: NSImage] = [:]

    static func image(_ kind: QuotaPetKind) -> NSImage {
        if let cached = cache[kind] { return cached }
        let sprite = QuotaPetArt.sprite(kind, size: .widget, mood: .idle, remaining: 72)
        let palette = QuotaPetArt.palette(kind, provider: .claude, tint: .original, remaining: 72)
        let image = NSImage(size: NSSize(width: sprite.width, height: sprite.height), flipped: true) { _ in
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    guard let color = palette[sprite.code(x: x, y: y)] else { continue }
                    NSColor(srgbRed: CGFloat((color >> 16) & 0xFF) / 255, green: CGFloat((color >> 8) & 0xFF) / 255,
                            blue: CGFloat(color & 0xFF) / 255, alpha: 1).setFill()
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        cache[kind] = image
        return image
    }
}
