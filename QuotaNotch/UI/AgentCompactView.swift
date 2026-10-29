// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// One state owns the silhouette, color and motion. The surrounding slot never animates.
struct AgentPaperGlyph: View {
    let state: AgentRunState
    var previewElapsed: Double? = nil
    var previewReducedMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    private var reduced: Bool { systemReduced || previewReducedMotion }
    @Environment(\.colorScheme) private var scheme
    @State private var origin = Date()
    @State private var completionSettled = false
    /// A failure pulses briefly, then holds still: an unread failure can sit in the notch for hours.
    @State private var failureSettled = false
    private var moving: Bool {
        state == .running || state == .waiting || (state == .failed && !failureSettled) || (state == .completed && !completionSettled)
    }
    private var ink: Color { Color.primary }
    private var paperBackground: Color { scheme == .dark ? .black : .white }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduced || !moving || previewElapsed != nil)) { timeline in
            let elapsed = previewElapsed ?? max(0, timeline.date.timeIntervalSince(origin))
            drawing(at: elapsed)
                .frame(width: 18, height: 18)
        }
        .accessibilityHidden(true)
        .task(id: state) {
            origin = Date(); completionSettled = false; failureSettled = false
            if state == .failed {
                completionSettled = true
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { failureSettled = true }
                return
            }
            failureSettled = true
            guard state == .completed else { completionSettled = true; return }
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { completionSettled = true }
        }
    }

    private func paper(_ accent: Color, coloredEdge: Bool = false, rules: Bool = true, opacity: Double = 1, neutralFold: Bool = false) -> some View {
        ZStack {
            AgentFoldedPage().fill(paperBackground)
            AgentFoldedPage().fill(accent.opacity(0.10))
            AgentFoldedPage().stroke(coloredEdge ? accent : ink.opacity(0.88),
                style: StrokeStyle(lineWidth: 1.05, lineCap: .round, lineJoin: .round))
            AgentPageFold().stroke(neutralFold ? ink.opacity(0.88) : accent.opacity(0.85),
                style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
            if rules {
                VStack(alignment: .leading, spacing: 2) {
                    Capsule().fill(ink.opacity(0.66)).frame(width: 5.3, height: 0.8)
                    Capsule().fill(accent.opacity(0.8)).frame(width: 3.3, height: 0.8)
                }.offset(x: -0.6, y: 1.6)
            }
        }.frame(width: 10.8, height: 13).opacity(opacity)
    }

    /// Every resting document shares the same front/back placement and silhouette.
    private func pageStack<Front: View>(spread: Double = 0.65, @ViewBuilder front: () -> Front) -> some View {
        ZStack {
            paper(ink, rules: false, opacity: 0.55).offset(x: -spread, y: -spread)
            front().offset(x: spread, y: spread)
        }
    }

    @ViewBuilder private func drawing(at elapsed: Double) -> some View {
        switch state {
        case .running:
            let x = reduced ? 1.5 : AgentGlyphMotion.pageX(at: elapsed)
            let y = reduced ? 1.3 : AgentGlyphMotion.pageY(at: elapsed)
            ZStack {
                paper(ink, rules: false, opacity: 0.70).offset(x: -x, y: -y).zIndex(-y)
                paper(AgentText.color(.running), coloredEdge: true)
                    .offset(x: x, y: y).zIndex(y)
            }
        case .waiting:
            ZStack {
                paper(ink, rules: false, opacity: 0.48).offset(x: -1.4, y: -0.8)
                AgentSpeechMark().fill(paperBackground)
                    .overlay { AgentSpeechMark().fill(AgentText.color(.waiting).opacity(0.14)) }
                    .overlay { AgentSpeechMark().stroke(AgentText.color(.waiting), style: StrokeStyle(lineWidth: 1.05, lineJoin: .round)) }
                    .overlay {
                        AgentReplyDots().fill(ink.opacity(0.94))
                    }
                    .frame(width: 12, height: 12)
                    .offset(x: 1.2, y: 0.5)
            }.offset(y: reduced ? 0 : AgentGlyphMotion.waitingOffset(at: elapsed))
        case .failed:
            pageStack {
                paper(AgentText.color(.failed), rules: false, neutralFold: true).overlay {
                    let glow = reduced ? 0 : AgentGlyphMotion.errorGlow(at: elapsed)
                    ZStack {
                        AgentCrossMark().stroke(AgentText.color(.failed), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                            .blur(radius: 1.4).opacity(glow)
                        AgentCrossMark().stroke(AgentText.color(.failed), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                            .shadow(color: AgentText.color(.failed).opacity(glow), radius: 0.8)
                    }
                    .frame(width: 4.2, height: 4.2)
                    .offset(x: -0.5)
                }
            }
        case .completed:
            let spread = reduced ? 0.65 : AgentGlyphMotion.completionSpread(at: elapsed)
            pageStack(spread: spread) {
                paper(AgentText.color(.completed), coloredEdge: true, rules: false)
                    .overlay {
                        VStack(alignment: .leading, spacing: 2) {
                            Capsule().fill(ink.opacity(0.7)).frame(width: 5, height: 0.8)
                            Capsule().fill(AgentText.color(.completed)).frame(width: 5, height: 1.6)
                        }.offset(y: 2.1)
                    }
            }
        case .interrupted:
            pageStack {
                paper(AgentText.color(.interrupted), rules: false, neutralFold: true).overlay {
                    HStack(spacing: 1.6) {
                        ForEach(0..<2) { _ in
                            RoundedRectangle(cornerRadius: 0.45).fill(AgentText.color(.interrupted))
                                .frame(width: 1.6, height: 5)
                        }
                    }.offset(y: 1.2)
                }
            }
        case .unknown:
            pageStack { paper(ink) }.opacity(0.40)
        }
    }
}

/// The folded corner gives task pages an identity without adding another badge or symbol.
private struct AgentFoldedPage: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let fold = r.width * 0.29, radius = r.width * 0.12
        p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}
private struct AgentPageFold: Shape {
    func path(in r: CGRect) -> Path {
        let fold = r.width * 0.29
        var p = Path()
        p.move(to: CGPoint(x: r.maxX - fold, y: r.minY + 0.2))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX - 0.2, y: r.minY + fold))
        return p
    }
}

/// A recognizable bubble rather than pause bars. Coordinates are normalized for tiny marks.
private struct AgentSpeechMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.2, y: 0.08))
        p.addLine(to: CGPoint(x: 0.8, y: 0.08))
        p.addQuadCurve(to: CGPoint(x: 0.94, y: 0.22), control: CGPoint(x: 0.94, y: 0.08))
        p.addLine(to: CGPoint(x: 0.94, y: 0.66))
        p.addQuadCurve(to: CGPoint(x: 0.8, y: 0.8), control: CGPoint(x: 0.94, y: 0.8))
        p.addLine(to: CGPoint(x: 0.45, y: 0.8))
        p.addLine(to: CGPoint(x: 0.19, y: 0.98))
        p.addLine(to: CGPoint(x: 0.23, y: 0.8))
        p.addLine(to: CGPoint(x: 0.2, y: 0.8))
        p.addQuadCurve(to: CGPoint(x: 0.06, y: 0.66), control: CGPoint(x: 0.06, y: 0.8))
        p.addLine(to: CGPoint(x: 0.06, y: 0.22))
        p.addQuadCurve(to: CGPoint(x: 0.2, y: 0.08), control: CGPoint(x: 0.06, y: 0.08))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
/// Align the reply dots to the bubble body (y: 0.08...0.80), excluding its tail.
private struct AgentReplyDots: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = rect.width * 0.10
        let centerY = rect.minY + rect.height * 0.44
        var path = Path()
        for centerX in [0.29, 0.50, 0.71] {
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * centerX - diameter / 2,
                                       y: centerY - diameter / 2, width: diameter, height: diameter))
        }
        return path
    }
}
private struct AgentCrossMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// The list uses the same artwork at six points, preserving its existing camera-side slot.
struct AgentTaskStateMark: View {
    static let size: CGFloat = 6
    let state: AgentRunState
    var animate = true
    var previewElapsed: Double? = nil
    var body: some View {
        AgentPaperGlyph(state: state, previewElapsed: previewElapsed, previewReducedMotion: !animate)
            .scaleEffect(Self.size / 18)
            .frame(width: Self.size, height: Self.size)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension Notification.Name {
    static let agentOpenNotch = Notification.Name("QuotaNotch.agentOpenNotch")
}

// The isolated preview observes the modules actually rendered, independently of fixture expectations.
// The installable build has no audit preferences or state.
#if SETTINGS_PREVIEW
struct NotchModuleFrameAuditKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct NotchModuleAuditKey: PreferenceKey {
    static var defaultValue: [String: String] = [:]
    static func reduce(value: inout [String: String], nextValue: () -> [String: String]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif
extension View {
    @ViewBuilder func auditNotchFrame(_ name: String) -> some View {
        #if SETTINGS_PREVIEW
        self.background(GeometryReader { proxy in
            Color.clear.preference(key: NotchModuleFrameAuditKey.self, value: [name: proxy.frame(in: .global)])
        })
        #else
        self
        #endif
    }
    @ViewBuilder func auditNotchModule(_ name: String, mode: String = "widget") -> some View {
        #if SETTINGS_PREVIEW
        self.preference(key: NotchModuleAuditKey.self, value: [name: mode]).auditNotchFrame(name)
        #else
        self
        #endif
    }
}
