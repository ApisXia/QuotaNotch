// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

enum QuotaBrand: CaseIterable, Equatable {
    case claude, codex
    var color: Color {
        self == .claude ? Color(red: 0.89, green: 0.61, blue: 0.48)
            : Color(red: 0.62, green: 0.83, blue: 0.75)
    }
}

/// Original small-size interpretations: asymmetric rays and a six-loop knot.
/// These are not official brand assets or SF Symbol substitutes.
struct QuotaBrandMark: View {
    let brand: QuotaBrand
    var muted = false
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ink = muted ? Color.gray : brand.color
            if brand == .claude {
                ClaudeRays().fill(ink)
                    .frame(width: side, height: side)
            } else {
                CodexKnot().stroke(ink, style: StrokeStyle(lineWidth: max(0.65, side * 0.07), lineCap: .round, lineJoin: .round))
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ClaudeRays: Shape {
    func path(in rect: CGRect) -> Path {
        let radii: [CGFloat] = [0.47, 0.42, 0.49, 0.44, 0.48, 0.40, 0.48, 0.45, 0.49, 0.43, 0.48, 0.41]
        let size = min(rect.width, rect.height)
        var p = Path()
        for i in 0..<36 {
            let ray = i / 3
            let offset: Double = i % 3 == 0 ? -0.045 : (i % 3 == 1 ? 0.045 : 0.26)
            let angle = Double(ray) * .pi / 6 + offset - .pi / 2
            let radius = (i % 3 == 2 ? 0.15 : radii[ray]) * size
            let point = CGPoint(x: rect.midX + CGFloat(cos(angle)) * radius, y: rect.midY + CGFloat(sin(angle)) * radius)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

private struct CodexKnot: Shape {
    func path(in rect: CGRect) -> Path {
        var result = Path()
        let size = min(rect.width, rect.height)
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.midX + (x * cos(angle) - y * sin(angle)) * size,
                        y: rect.midY + (x * sin(angle) + y * cos(angle)) * size)
            }
            result.move(to: point(-0.08, -0.17))
            result.addLine(to: point(-0.08, -0.34))
            result.addCurve(to: point(0.27, -0.34), control1: point(-0.08, -0.52), control2: point(0.22, -0.52))
            result.addLine(to: point(0.36, -0.18))
            result.addLine(to: point(0.10, -0.03))
        }
        return result
    }
}

/// The complete silhouette, including its badge, stays inside the music icon's box.
struct CompactQuotaGauge: View {
    let brand: QuotaBrand
    let percent: Double?
    var stale = false
    var showsBrand = false
    let size: CGFloat

    var body: some View {
        let stroke = max(1, min(1.8, size * 0.085))
        let inset = stroke / 2 + 0.5
        ZStack {
            Circle().inset(by: inset)
                .stroke(.white.opacity(0.20), style: StrokeStyle(lineWidth: stroke, dash: percent == nil ? [1.5, 2] : []))
            if let percent {
                Circle().inset(by: inset).trim(from: 0, to: min(1, max(0, percent / 100)))
                    .stroke(stale ? .gray : brand.color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Text("—").font(.system(size: max(5, size * 0.37), weight: .medium)).foregroundStyle(.gray)
            }
            if stale {
                Circle().fill(.orange.opacity(0.85)).frame(width: 3, height: 3)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showsBrand && size >= 12 {
                QuotaBrandMark(brand: brand, muted: stale)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .padding(size * 0.05)
                    .background(.black, in: Circle())
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.3), value: percent)
        .accessibilityHidden(true)
    }
}
