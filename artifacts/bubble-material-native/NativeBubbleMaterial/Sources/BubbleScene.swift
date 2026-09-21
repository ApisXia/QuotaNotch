import SwiftUI

struct BubbleScene: View {
    let time: TimeInterval
    let light: SIMD2<Float>
    let populated: Bool
    let arrival: ArrivalFrame

    private let bubbleDiameter: CGFloat = 226

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Backdrop()

                bubble
                    .frame(width: bubbleDiameter, height: bubbleDiameter)
                    .scaleEffect(arrival.shellScale)
                    .opacity(arrival.shellOpacity)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 512, height: 512)
        .environment(\.colorScheme, .dark)
    }

    private var bubble: some View {
        let breathing = BubbleMotion.breathing(at: time, populated: populated)
        let shader = ShaderLibrary.default.pearlFilm(
            .boundingRect,
            .float(Float(time)),
            .float2(CGPoint(x: CGFloat(light.x), y: CGFloat(light.y))),
            .float(populated ? 1 : 0),
            .float(Float(breathing))
        )

        return ZStack {
            PearlyBubbleShape(time: time, breathing: breathing)
                .fill(shader)
                .overlay {
                    PearlyBubbleShape(time: time, breathing: breathing)
                        .stroke(.white.opacity(0.20), lineWidth: 0.7)
                }
                .shadow(color: Color(red: 0.40, green: 0.67, blue: 0.84).opacity(0.18), radius: 23, y: 9)

            if populated {
                ForEach(0..<3, id: \.self) { index in
                    Flake(index: index, time: time, gather: arrival.flakeGather)
                        .opacity(arrival.flakeOpacity)
                }
            }

            DoubleBubbleMark()
                .frame(width: 42, height: 42)
                .opacity(0.72)
        }
    }
}

private struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.043, blue: 0.070)
            RadialGradient(
                colors: [Color(red: 0.24, green: 0.31, blue: 0.43).opacity(0.38), .clear],
                center: UnitPoint(x: 0.33, y: 0.29),
                startRadius: 0,
                endRadius: 330
            )
            RadialGradient(
                colors: [Color(red: 0.28, green: 0.29, blue: 0.39).opacity(0.20), .clear],
                center: UnitPoint(x: 0.74, y: 0.71),
                startRadius: 0,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

private struct PearlyBubbleShape: Shape {
    var time: TimeInterval
    var breathing: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.5
        let radiusY = rect.height * 0.5
        let phase = time * 0.31
        let amount = 0.010 + Double(breathing) * 0.006
        var path = Path()

        for step in 0...96 {
            let angle = Double(step) / 96 * 2 * .pi
            let softWave = sin(angle * 3 + phase) * amount + cos(angle * 2 - phase * 0.72) * amount * 0.48
            let radius = 1 + softWave
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radiusX * CGFloat(radius),
                y: center.y + CGFloat(sin(angle)) * radiusY * CGFloat(radius)
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct Flake: View {
    let index: Int
    let time: TimeInterval
    let gather: CGFloat

    private let angles = [-2.62, -0.48, 1.62]
    private let phases = [0.20, 2.25, 4.12]

    var body: some View {
        let angle = angles[index] + sin(time * 0.31 + phases[index]) * 0.12
        let radius = 52 * (1 - gather) + 12 * gather + CGFloat(sin(time * 0.52 + phases[index]) * 3)
        let opacity = 0.54 + 0.23 * (0.5 + 0.5 * sin(time * 0.78 + phases[index]))

        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.14),
                        Color(red: 0.79, green: 0.90, blue: 0.98).opacity(0.82),
                        Color(red: 0.88, green: 0.80, blue: 0.91).opacity(0.52),
                        .white.opacity(0.12)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: index == 1 ? 22 : 17, height: 1.2)
            .rotationEffect(.radians(Double(angle) + 0.52))
            .shadow(color: .white.opacity(0.35), radius: 2)
            .position(x: 113 + CGFloat(cos(angle)) * radius, y: 113 + CGFloat(sin(angle)) * radius)
            .opacity(opacity)
    }
}

/// A quiet two-layer notch mark: the rear loop disappears under the softly
/// filled front loop, so the outlines never read as crossing wire circles.
private struct DoubleBubbleMark: View {
    var body: some View {
        ZStack {
            RearBubbleArc()
                .stroke(.white.opacity(0.30), lineWidth: 0.9)
                .frame(width: 24, height: 24)
                .offset(x: 5, y: -4)

            Circle()
                .fill(Color(red: 0.70, green: 0.82, blue: 0.90).opacity(0.58))
                .overlay {
                    Circle().stroke(.white.opacity(0.58), lineWidth: 0.9)
                }
                .frame(width: 25, height: 25)
                .offset(x: -4, y: 3)
        }
        .shadow(color: .white.opacity(0.14), radius: 4)
    }
}

private struct RearBubbleArc: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5
        var path = Path()
        for step in 0...48 {
            let angle = -1.30 + Double(step) / 48 * 1.72
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
