// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

extension Notification.Name { static let notchCatCue = Notification.Name("QuotaNotch.catCue") }

private struct CatPoseKey: EnvironmentKey { static let defaultValue = CatPose() }
extension EnvironmentValues {
    var notchCatPose: CatPose {
        get { self[CatPoseKey.self] }
        set { self[CatPoseKey.self] = newValue }
    }
}
struct CatWingOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

/// One director per notch window: one cat, one clock, no global keyboard/mouse monitoring.
@MainActor final class NotchCatDirector: ObservableObject {
    @Published var pose = CatPose()
    var queue = CatCueQueue()
    private var hovering = false
    private var resumeAt = Date.distantPast
    func pointer(_ inside: Bool) {
        hovering = inside
        if !inside { resumeAt = Date().addingTimeInterval(2) }
    }
    private var paused: Bool { hovering || Date() < resumeAt }
    func cue(_ action: CatAction) { queue.enqueue(action, now: Date()) }
    func run(left: CatWingSpace, right: CatWingSpace, reduced: Bool) async {
        defer { pose = CatPose() }
        #if SETTINGS_PREVIEW
        return
        #else
        let sides = CatSide.allCases.filter { ($0 == .left ? left : right).canPeek }
        guard !sides.isEmpty else { return }
        var next = Date().addingTimeInterval(4)
        var lastSide: CatSide = .left
        while !Task.isCancelled {
            let now = Date()
            if paused {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                continue
            }
            let cue = queue.take(now: now)
            if cue != nil || now >= next {
                let side = sides.first { $0 != lastSide } ?? sides[0]
                lastSide = side
                let action = cue ?? (Bool.random() ? .curious : .rest)
                if reduced {
                    pose = CatPose(side: side, action: action, elapsed: 4, active: true)
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                } else {
                    var elapsed: Double = 0
                    var previous = Date()
                    while elapsed < CatPose.duration {
                        let current = Date()
                        if !paused { elapsed += min(0.1, current.timeIntervalSince(previous)) }
                        previous = current
                        pose = CatPose(side: side, action: action, elapsed: elapsed, active: true)
                        do { try await Task.sleep(for: .milliseconds(paused ? 150 : 33)) } catch { return }
                    }
                }
                pose = CatPose()
                next = Date().addingTimeInterval(Double.random(in: 24...48))
            }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
        #endif
    }
}

/// The inner corridor grows toward the camera, moving only this wing's existing content outward.
/// Its width preference compensates the shell center so the physical camera stays anchored.
private struct CatWingModifier: ViewModifier {
    let side: CatSide
    let occupied: CGFloat
    let height: CGFloat
    @Environment(\.notchCatPose) private var pose
    private var space: CatWingSpace {
        let widget = QuotaCompactMetrics.iconSize(height: height)
        return CatWingSpace(occupied: occupied, limit: widget + NotchModuleMetrics(widgetWidth: widget).additionalWidth)
    }
    func body(content: Content) -> some View {
        let visible = pose.active && pose.side == side && space.canPeek
        let width = visible ? space.excursion * pose.extensionAmount : 0
        HStack(spacing: 0) {
            if side == .right { Color.clear.frame(width: width) }
            content
            if side == .left { Color.clear.frame(width: width) }
        }
        .frame(height: height)
        .overlay(alignment: side == .left ? .trailing : .leading) {
            if visible {
                NotchCatDrawing(pose: pose, empty: space.isEmpty)
                    .frame(width: space.excursion + 5, height: min(26, height - 4))
                    .scaleEffect(x: side == .left ? -1 : 1, y: 1)
                    .frame(width: width + 5, height: height, alignment: side == .left ? .trailing : .leading)
                    .clipped()
                    .offset(x: side == .left ? 5 : -5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .preference(key: CatWingOffsetKey.self, value: (side == .left ? -width : width) / 2)
    }
}
extension View {
    func catWing(_ side: CatSide, occupied: CGFloat, height: CGFloat) -> some View {
        modifier(CatWingModifier(side: side, occupied: occupied, height: height))
    }
}

/// Original vector character, drawn as articulated parts in a 32 × 26 coordinate space.
/// The dark ear/face details remain legible at native notch size.
struct NotchCatDrawing: View {
    let pose: CatPose
    var empty = false
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 32, y: size.height / 26)
            let t = pose.elapsed
            let head = pose.headAmount
            let x = -15 + 28 * head
            let sleepy = pose.action == .rest && t > 2.8 && t < 6.7
            let y = sleepy ? 15.0 : 12.0 + sin(t * 1.7) * 0.45
            let ink = Color(white: 0.91)
            let shade = Color(white: 0.66)
            func ellipse(_ rect: CGRect, _ color: Color) { context.fill(Path(ellipseIn: rect), with: .color(color)) }
            func line(_ points: [CGPoint], color: Color, width: CGFloat = 1) {
                var p = Path(); if let first = points.first { p.move(to: first) }
                for point in points.dropFirst() { p.addLine(to: point) }
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            if empty && head > 0.1 {
                // Curled body and a gently settling tail, behind the face.
                var tail = Path(); tail.move(to: CGPoint(x: x - 2, y: 22))
                tail.addCurve(to: CGPoint(x: x + 13, y: 14 + sin(t * 1.4)),
                              control1: CGPoint(x: x + 17, y: 26), control2: CGPoint(x: x + 16, y: 15))
                context.stroke(tail, with: .color(shade), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                ellipse(CGRect(x: x - 10, y: 14, width: 19, height: 11), shade)
            }
            // Ear silhouettes, rounded head and inset ears share the existing icon palette.
            var ears = Path()
            ears.move(to: CGPoint(x: x - 8, y: y))
            ears.addLine(to: CGPoint(x: x - 8.4, y: y - 10))
            ears.addQuadCurve(to: CGPoint(x: x - 2, y: y - 6), control: CGPoint(x: x - 7, y: y - 11))
            ears.addLine(to: CGPoint(x: x + 3, y: y - 6))
            ears.addQuadCurve(to: CGPoint(x: x + 8.4, y: y - 10), control: CGPoint(x: x + 8, y: y - 12))
            ears.addLine(to: CGPoint(x: x + 9, y: y + 1)); ears.closeSubpath()
            context.fill(ears, with: .color(ink))
            ellipse(CGRect(x: x - 9.5, y: y - 6.5, width: 19, height: 15), ink)
            line([CGPoint(x: x - 6.5, y: y - 7.8), CGPoint(x: x - 5, y: y - 5.7)], color: shade, width: 1.5)
            line([CGPoint(x: x + 6.6, y: y - 7.9), CGPoint(x: x + 5.2, y: y - 5.7)], color: shade, width: 1.5)
            for eye in [-3.4, 3.4] {
                if pose.blink || sleepy {
                    line([CGPoint(x: x + eye - 1, y: y + 0.3), CGPoint(x: x + eye + 1, y: y + 0.3)], color: .black)
                } else {
                    ellipse(CGRect(x: x + eye - 0.65, y: y - 1, width: 1.3, height: 2.3), .black)
                }
            }
            ellipse(CGRect(x: x - 0.8, y: y + 2.6, width: 1.6, height: 1.1), Color(white: 0.25))
            line([CGPoint(x: x, y: y + 3.6), CGPoint(x: x - 1.2, y: y + 4.5)], color: Color(white: 0.4), width: 0.65)
            line([CGPoint(x: x, y: y + 3.6), CGPoint(x: x + 1.2, y: y + 4.5)], color: Color(white: 0.4), width: 0.65)
            // The pushing paw stays on the advancing outer edge; a cue raises it once.
            let lift = pose.action == .completed ? sin(max(0, min(1, (t - 2.6) / 2.2)) * .pi) * 5 : 0
            let tap = pose.action == .attention && t > 2.5 && t < 4.5 ? abs(sin((t - 2.5) * .pi)) * 2 : 0
            let pawX = 1 + 24 * pose.extensionAmount
            ellipse(CGRect(x: pawX - 4, y: 18 - lift - tap, width: 6 * pose.pawAmount, height: 5), ink)
            line([CGPoint(x: pawX - 1, y: 21 - lift - tap), CGPoint(x: pawX - 1, y: 22 - lift - tap)], color: shade, width: 0.65)
        }
    }
}

struct NotchCatSettings: View {
    @AppStorage("notchCatEnabled") private var enabled = true
    @AppStorage("notchCatTaskCues") private var taskCues = true
    var body: some View {
        Section {
            Toggle(AgentText.t("刘海猫猫", "Notch cat"), isOn: $enabled)
            if enabled {
                Toggle(AgentText.t("任务提示动作", "Task reactions"), isOn: $taskCues)
            }
        } header: { Text(AgentText.t("猫猫", "Cat")) } footer: {
            Text(AgentText.t("在两侧空余处探头，轻推有余量的组件。操作刘海时会让位。", "Peeks out beside the notch and gently nudges widgets when there is room. Gives way while you use the notch."))
        }
    }
}
