// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Redraws only while the pet moves: every frame while animating, around blinks while
/// resting, and rarely otherwise.
struct QuotaPetSchedule: TimelineSchedule {
    let mood: @Sendable (Date) -> QuotaPetMood
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        var first = true
        return AnyIterator {
            if first { first = false; return next }
            next = QuotaPetArt.nextRedraw(after: next, mood: mood(next))
            return next
        }
    }
}

/// The closed-notch quota pet. One sprite pixel is one point (times `scale`).
struct QuotaPetView: View {
    let kind: QuotaPetKind
    let size: QuotaPetSize
    let provider: QuotaProvider
    let window: QuotaWindow?
    let stale: Bool
    var scale: CGFloat = 1
    /// Overrides the tracked mood (settings previews).
    var fixedMood: QuotaPetMood? = nil
    @ObservedObject private var store = QuotaNotchStore.shared
    @AppStorage(QuotaPetTint.defaultsKey) private var tintRaw = QuotaPetTint.original.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var key: String { QuotaPetTracker.key(provider: provider, windowID: window?.id ?? "") }
    private var tint: QuotaPetTint { QuotaPetTint(rawValue: tintRaw) ?? .original }

    /// A value-only mood function, safe to evaluate from the timeline schedule.
    private var moodAt: @Sendable (Date) -> QuotaPetMood {
        let tracker = store.petTracker, fixed = fixedMood, slot = self.key, reading = self.window, old = self.stale
        return { date in fixed ?? tracker.mood(key: slot, window: reading, stale: old, now: date) }
    }

    var body: some View {
        let moodFor = self.moodAt
        Group {
            if reduceMotion {
                pet(mood: moodFor(Date()), frame: 0, blink: false)
            } else {
                TimelineView(QuotaPetSchedule(mood: moodFor)) { context in
                    let current = moodFor(context.date)
                    pet(mood: current, frame: current.animates ? QuotaPetArt.frame(at: context.date) : 0,
                        blink: QuotaPetArt.blinking(at: context.date))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func pet(mood: QuotaPetMood, frame: Int, blink: Bool) -> some View {
        let remaining = window?.remainingPercent ?? 0
        let sprite = QuotaPetArt.sprite(kind, size: size, mood: mood, remaining: remaining, frame: frame, blink: blink)
        let palette = QuotaPetArt.palette(kind, provider: provider, tint: tint, remaining: remaining)
        return QuotaPetPixels(sprite: sprite, palette: palette, scale: scale)
            .saturation(mood == .stale ? 0 : 1)
            .opacity(mood == .stale ? 0.55 : 1)
    }
}

/// Draws a sprite as filled squares, one path per color.
struct QuotaPetPixels: View {
    let sprite: QuotaPetSprite
    let palette: [UInt8: UInt32]
    let scale: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            var paths: [UInt32: Path] = [:]
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    guard let color = palette[sprite.code(x: x, y: y)] else { continue }
                    paths[color, default: Path()].addRect(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale))
                }
            }
            for (color, path) in paths {
                context.fill(path, with: .color(Color(quotaPetRGB: color)))
            }
        }
        .frame(width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale)
    }
}

extension Color {
    init(quotaPetRGB value: UInt32) {
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}

/// The remaining percentage beside the pet when quota has both wings to itself, with a
/// horizontal bar in the pet's own gauge color underneath.
struct QuotaPetPercent: View {
    let percent: Double?
    let stale: Bool
    let kind: QuotaPetKind
    let provider: QuotaProvider
    let tint: QuotaPetTint
    var fontSize: CGFloat = 12
    var body: some View {
        let value = percent.map { min(100, max(0, $0)) }
        let ink: Color = {
            guard let value, !stale else { return .gray }
            if value < 20 { return Color(quotaPetRGB: 0xFF6B5E) }
            if value < 35 { return Color(quotaPetRGB: 0xF4D35E) }
            return .white
        }()
        let bar: Color = value.map { stale ? .gray : Color(quotaPetRGB: QuotaPetArt.gaugeColor(kind, provider: provider, tint: tint, remaining: $0)) } ?? .gray
        VStack(spacing: max(2, fontSize * 0.2)) {
            Text(value.map { QuotaText.percent($0) + "%" } ?? "—")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(ink)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(bar).frame(width: proxy.size.width * CGFloat((value ?? 0) / 100))
                }
            }
            .frame(height: fontSize >= 13 ? 3 : 2)
        }
        .padding(.horizontal, 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}
