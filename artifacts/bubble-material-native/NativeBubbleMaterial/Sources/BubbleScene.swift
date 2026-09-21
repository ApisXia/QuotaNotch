import SwiftUI

struct BubbleScene: View {
    let time: TimeInterval
    let light: SIMD2<Float>
    let itemCount: Int
    let insertionFrame: BubbleInsertionFrame?
    let arrival: ArrivalFrame
    let canvasSize: CGSize
    let bubbleDiameter: CGFloat
    let backdropStyle: BubbleBackdropStyle
    let showsBubble: Bool
    let showsFourthPreview: Bool
    let drawBackdrop: Bool

    init(
        time: TimeInterval,
        light: SIMD2<Float>,
        itemCount: Int,
        insertionFrame: BubbleInsertionFrame? = nil,
        arrival: ArrivalFrame,
        canvasSize: CGSize = CGSize(width: 512, height: 512),
        bubbleDiameter: CGFloat = 226,
        backdropStyle: BubbleBackdropStyle = .night,
        showsBubble: Bool = true,
        showsFourthPreview: Bool = true,
        drawBackdrop: Bool = true
    ) {
        self.time = time
        self.light = light
        self.itemCount = itemCount
        self.insertionFrame = insertionFrame
        self.arrival = arrival
        self.canvasSize = canvasSize
        self.bubbleDiameter = bubbleDiameter
        self.backdropStyle = backdropStyle
        self.showsBubble = showsBubble
        self.showsFourthPreview = showsFourthPreview
        self.drawBackdrop = drawBackdrop
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if drawBackdrop {
                    Backdrop(style: backdropStyle)
                }

                if showsBubble {
                    bubble
                        .frame(width: bubbleDiameter, height: bubbleDiameter)
                        .scaleEffect(arrival.shellScale)
                        .opacity(arrival.shellOpacity)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .environment(\.colorScheme, backdropStyle == .night ? .dark : .light)
    }

    private var bubble: some View {
        let breathing = BubbleMotion.breathing(at: time, populated: itemCount > 0)
        let shader = ShaderLibrary.default.pearlFilm(
            .boundingRect,
            .float(Float(time)),
            .float2(CGPoint(x: CGFloat(light.x), y: CGFloat(light.y))),
            .float(itemCount > 0 ? 1 : 0),
            .float(Float(breathing))
        )

        let shell = PearlyBubbleShape(time: time, breathing: breathing)
        return ZStack {
            if itemCount > 0 {
                BubbleContentPreviews(
                    totalCount: itemCount,
                    time: time,
                    gather: arrival.contentGather,
                    bubbleDiameter: bubbleDiameter,
                    insertionFrame: insertionFrame,
                    showsFourthPreview: showsFourthPreview
                )
                .opacity(arrival.contentOpacity)
            }

            shell
                .fill(shader)
                .overlay {
                    shell.stroke(.white.opacity(0.20), lineWidth: 0.7)
                }
        }
        .frame(width: bubbleDiameter, height: bubbleDiameter)
        .clipShape(shell)
        .shadow(
            color: Color(red: 0.40, green: 0.67, blue: 0.84).opacity(0.18),
            radius: max(6, bubbleDiameter * 0.10),
            y: bubbleDiameter * 0.04
        )
    }
}

enum BubbleBackdropStyle: Equatable {
    case night
    case pearl
    case patterned
}

struct Backdrop: View {
    let style: BubbleBackdropStyle

    var body: some View {
        ZStack {
            if style == .night {
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
            } else if style == .pearl {
                Color(red: 0.91, green: 0.91, blue: 0.94)
                RadialGradient(
                    colors: [Color(red: 1.00, green: 0.96, blue: 0.93).opacity(0.90), .clear],
                    center: UnitPoint(x: 0.31, y: 0.25),
                    startRadius: 0,
                    endRadius: 285
                )
                RadialGradient(
                    colors: [Color(red: 0.77, green: 0.84, blue: 0.91).opacity(0.33), .clear],
                    center: UnitPoint(x: 0.77, y: 0.72),
                    startRadius: 0,
                    endRadius: 310
                )
            } else {
                Color(red: 0.12, green: 0.15, blue: 0.20)
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let tile: CGFloat = 64
                    for row in -6...6 {
                        for column in -6...6 where (row + column).isMultiple(of: 2) {
                            let rect = CGRect(
                                x: center.x + CGFloat(column) * tile,
                                y: center.y + CGFloat(row) * tile,
                                width: tile,
                                height: tile
                            )
                            let color = (row - column).isMultiple(of: 4)
                                ? Color(red: 0.23, green: 0.40, blue: 0.52)
                                : Color(red: 0.48, green: 0.31, blue: 0.41)
                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }
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

/// A quiet two-layer notch mark: the rear loop disappears under the softly
/// filled front loop, so the outlines never read as crossing wire circles.
struct DoubleBubbleMark: View {
    var size: CGFloat = 28

    private var unit: CGFloat { size / 28 }

    var body: some View {
        ZStack {
            RearBubbleArc()
                .stroke(.white.opacity(0.30), lineWidth: max(0.42, 0.9 * unit))
                .frame(width: 24 * unit, height: 24 * unit)
                .offset(x: 2 * unit, y: -1.5 * unit)

            Circle()
                .fill(Color(red: 0.70, green: 0.82, blue: 0.90).opacity(0.58))
                .overlay {
                    Circle().stroke(.white.opacity(0.58), lineWidth: max(0.42, 0.9 * unit))
                }
                .frame(width: 24 * unit, height: 24 * unit)
                .offset(x: -1.5 * unit, y: 1.5 * unit)
        }
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.14), radius: size < 24 ? size * 0.035 : 4 * unit)
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
