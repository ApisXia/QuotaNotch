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

extension QuotaPetTasks {
    init(_ summary: AgentAttentionSummary, enabled: Bool) {
        self.init()
        guard enabled else { return }
        waiting = summary.waiting
        running = summary.running
        lastCompletedAt = summary.lastCompletedAt
    }
}

/// The closed-notch pet. One sprite pixel is one point (times `scale`). It reflects quota on
/// its body and tasks through its pose and the effect around it.
struct QuotaPetView: View {
    let kind: QuotaPetKind
    let size: QuotaPetSize
    let provider: QuotaProvider
    let window: QuotaWindow?
    let stale: Bool
    var scale: CGFloat = 1
    var tasks: QuotaPetTasks = .none
    /// Overrides the tracked mood (settings previews).
    var fixedMood: QuotaPetMood? = nil
    var fixedSignal: QuotaPetSignal = .none
    /// Pixel ripples: the size of one ripple pixel and how far out they reach, in points.
    /// Defaults to the pet's own pixels and the full effect margin; a tight space (the opened
    /// panel's column) uses finer, closer ripples so every ring fits.
    var rippleCell: CGFloat? = nil
    var rippleReach: CGFloat? = nil
    @ObservedObject private var store = QuotaNotchStore.shared
    @AppStorage(QuotaPetTint.defaultsKey) private var tintRaw = QuotaPetTint.original.rawValue
    @AppStorage(QuotaPetEffect.defaultsKey) private var effectRaw = QuotaPetEffect.soft.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var key: String { QuotaPetTracker.key(provider: provider, windowID: window?.id ?? "") }
    private var tint: QuotaPetTint { QuotaPetTint(rawValue: tintRaw) ?? .original }
    private var effect: QuotaPetEffect { QuotaPetEffect(rawValue: effectRaw) ?? .soft }

    /// A value-only state function, safe to evaluate from the timeline schedule.
    private var stateAt: @Sendable (Date) -> (mood: QuotaPetMood, signal: QuotaPetSignal) {
        let tracker = store.petTracker, fixed = fixedMood, signal = fixedSignal
        let slot = self.key, reading = self.window, old = self.stale, work = self.tasks
        return { date in
            if let fixed { return (fixed, signal) }
            return QuotaPetBehavior.resolve(quota: tracker.mood(key: slot, window: reading, stale: old, now: date),
                                            tasks: work, now: date)
        }
    }

    var body: some View {
        let stateFor = self.stateAt
        Group {
            if reduceMotion {
                let state = stateFor(Date())
                pet(mood: state.mood, signal: state.signal, frame: 0, blink: false)
            } else {
                TimelineView(QuotaPetSchedule(mood: { stateFor($0).mood })) { context in
                    let state = stateFor(context.date)
                    pet(mood: state.mood, signal: state.signal,
                        frame: state.mood.animates ? QuotaPetArt.frame(at: context.date) : 0,
                        blink: QuotaPetArt.blinking(at: context.date))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func pet(mood: QuotaPetMood, signal: QuotaPetSignal, frame: Int, blink: Bool) -> some View {
        let remaining = window?.remainingPercent ?? 0
        let sprite = QuotaPetArt.sprite(kind, size: size, mood: mood, remaining: remaining, frame: frame, blink: blink)
        let palette = QuotaPetArt.palette(kind, provider: provider, tint: tint, remaining: remaining)
        let theme = Color(quotaPetRGB: QuotaPetArt.themeColor(kind))
        return QuotaPetPixels(sprite: sprite, palette: palette, scale: scale)
            .saturation(mood == .stale ? 0 : 1)
            .opacity(mood == .stale ? 0.55 : 1)
            .background {
                if signal != .none {
                    QuotaPetEffectLayer(style: effect, signal: signal, sprite: sprite, scale: scale, color: theme, front: false,
                                        rippleCell: rippleCell, rippleReach: rippleReach)
                }
            }
            .overlay {
                if signal != .none {
                    QuotaPetEffectLayer(style: effect, signal: signal, sprite: sprite, scale: scale, color: theme, front: true)
                }
            }
    }
}

/// Running and waiting effects. Each style keeps one shape for both signals and only changes
/// pace and brightness: running is slow and faint, waiting is quick and bright.
struct QuotaPetEffectLayer: View {
    let style: QuotaPetEffect
    let signal: QuotaPetSignal
    let sprite: QuotaPetSprite
    let scale: CGFloat
    let color: Color
    /// Drawn above the pixels (the pixel outline) or behind them (everything else).
    let front: Bool
    var rippleCell: CGFloat? = nil
    var rippleReach: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var margin: CGFloat { 8 * scale }
    /// Ripple pixels per sprite pixel (a whole number), and ripple pixels per point.
    private var rippleFactor: Int { max(1, Int((scale / (rippleCell ?? scale)).rounded())) }
    private var cell: CGFloat { scale / CGFloat(rippleFactor) }
    private var rippleRings: Int { max(2, min(Int((rippleReach ?? margin) / cell), Int(margin / cell))) }
    private var width: CGFloat { CGFloat(sprite.width) * scale + 2 * margin }
    private var height: CGFloat { CGFloat(sprite.height) * scale + 2 * margin }
    private var interval: TimeInterval { style == .soft ? 1.0 / 15 : 0.1 }

    var body: some View {
        Group {
            if reduceMotion {
                canvas(time: nil)
            } else {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func canvas(time: TimeInterval?) -> some View {
        // Every other ring out to the reach, so the ripple travels as far as the soft rings.
        let contours = style == .pixel && signal == .running && !front
            ? sprite.upscaled(rippleFactor).contours(maxDistance: rippleRings)
                .enumerated().filter { $0.offset % 2 == 1 }.map(\.element) : []
        let outline = style == .pixel && signal == .waiting && front ? sprite.outlineCells : []
        return Canvas(rendersAsynchronously: false) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = max(CGFloat(sprite.width), CGFloat(sprite.height)) * scale * 0.62
            func pixels(_ cells: [QuotaPetCell], opacity: Double, size: CGFloat? = nil) {
                let side = size ?? scale
                var path = Path()
                for cell in cells {
                    path.addRect(CGRect(x: margin + CGFloat(cell.x) * side, y: margin + CGFloat(cell.y) * side, width: side, height: side))
                }
                context.fill(path, with: .color(color.opacity(opacity)))
            }
            func ring(progress: Double, peak: Double) {
                let radius = reach * (0.35 + 0.8 * progress)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(peak * (1 - progress))), lineWidth: max(1, scale))
            }
            switch (style, signal, front) {
            case (.soft, .running, false):
                guard let time else { return }
                let p = (time / 2.8).truncatingRemainder(dividingBy: 1)
                // Clearly visible, still calmer than waiting (faster rings and a glow).
                ring(progress: p, peak: 0.55)
                ring(progress: (p + 0.5).truncatingRemainder(dividingBy: 1), peak: 0.55)
            case (.soft, .waiting, false):
                let wave = time.map { 0.5 + 0.5 * cos($0 / 1.2 * 2 * .pi) } ?? 0.6
                var glow = context
                glow.addFilter(.blur(radius: 5 * scale))
                let r = reach * 0.75
                glow.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                          with: .color(color.opacity(0.12 + 0.6 * wave)))
                if let time {
                    let p = (time / 1.2).truncatingRemainder(dividingBy: 1)
                    ring(progress: p, peak: 0.75)
                    ring(progress: (p + 0.5).truncatingRemainder(dividingBy: 1), peak: 0.75)
                }
            case (.pixel, .running, false):
                guard let time, !contours.isEmpty else { return }
                let step = Int(time / 0.6) % contours.count
                pixels(contours[step], opacity: [0.6, 0.45, 0.3, 0.16][min(step, 3)], size: cell)
                // A faint trail one step behind keeps the wave readable at a distance.
                if step > 0 { pixels(contours[step - 1], opacity: 0.12, size: cell) }
            case (.pixel, .waiting, true):
                let lit = time.map { Int($0 / 0.5) % 2 == 0 } ?? true
                if lit { pixels(outline, opacity: 1) }
            default:
                break
            }
        }
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

/// A dot that fades in and out (waiting tasks).
struct QuotaPetPulse<Content: View>: View {
    var active: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        content()
            .opacity(active && dim ? 0.3 : 1)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// The cell beside the pet: remaining quota on top; below it the quota bar in the pet's gauge
/// color, followed by one dot per task, in the same colors as the task list.
struct QuotaPetSummary: View {
    let percent: Double?
    let stale: Bool
    let kind: QuotaPetKind
    let provider: QuotaProvider
    let tint: QuotaPetTint
    var fontSize: CGFloat = 12
    var tasks: [AgentRunState] = []

    var body: some View {
        let value = percent.map { min(100, max(0, $0)) }
        let ink: Color = {
            guard let value, !stale else { return .gray }
            if value < 20 { return Color(quotaPetRGB: 0xFF6B5E) }
            if value < 35 { return Color(quotaPetRGB: 0xF4D35E) }
            return .white
        }()
        let bar: Color = value.map { stale ? .gray : Color(quotaPetRGB: QuotaPetArt.gaugeColor(kind, provider: provider, tint: tint, remaining: $0)) } ?? .gray
        let dot = max(3, fontSize * 0.3)
        let shown = Array(tasks.prefix(3))
        VStack(spacing: max(2, fontSize * 0.22)) {
            Text(value.map { QuotaText.percent($0) + "%" } ?? "—")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(ink)
            HStack(spacing: max(1.5, dot * 0.5)) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(bar).frame(width: proxy.size.width * CGFloat((value ?? 0) / 100))
                    }
                }
                .frame(height: fontSize >= 13 ? 3 : 2)
                ForEach(Array(shown.enumerated()), id: \.offset) { _, state in
                    QuotaPetPulse(active: state == .waiting) {
                        Circle().fill(AgentText.color(state)).frame(width: dot, height: dot)
                    }
                }
                if tasks.count > 3 {
                    Text(verbatim: "+\(tasks.count - 3)")
                        .font(.system(size: max(7, fontSize * 0.62), weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize()
                }
            }
            .frame(height: dot)
        }
        .padding(.horizontal, 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// With music: a small dark tag on the pet's bottom-right, matching the album's playback tag.
/// Running tasks hop like the album's bars; waiting shows a blinking "!"; finished shows a check.
struct QuotaPetTaskBadge: View {
    let states: [AgentRunState]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let state = states.first {
            Group {
                switch state {
                case .running:
                    if reduceMotion {
                        dots(phase: 0)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
                            dots(phase: context.date.timeIntervalSinceReferenceDate)
                        }
                    }
                case .waiting, .failed:
                    QuotaPetPulse(active: true) { mark("!", state: state) }
                default:
                    mark("✓", state: state)
                }
            }
            .frame(width: 9, height: 7)
            .padding(1)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func dots(phase: TimeInterval) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { index in
                let t = (phase - Double(index) * 0.15).truncatingRemainder(dividingBy: 1)
                let lift = t >= 0 && t < 0.3 ? sin(t / 0.3 * .pi) * 1.5 : 0
                Circle().fill(AgentText.color(.running)).frame(width: 2, height: 2)
                    .offset(y: -lift)
            }
        }
    }

    private func mark(_ text: String, state: AgentRunState) -> some View {
        Text(verbatim: text)
            .font(.system(size: 7, weight: .heavy, design: .rounded))
            .foregroundStyle(AgentText.color(state))
    }
}
