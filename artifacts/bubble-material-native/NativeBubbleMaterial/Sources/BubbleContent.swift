import AppKit
import SwiftUI

enum BubbleDemoContent: String, CaseIterable, Hashable, Identifiable {
    case stillLife
    case document
    case diagram
    case stillLifeDetail
    case report
    case fieldNotes

    var id: String { rawValue }
}

struct BubblePreviewPlacement: Identifiable, Equatable {
    let slot: Int
    let content: BubbleDemoContent
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let opacity: Double
    let depth: Double
    let drift: CGFloat

    var id: Int { slot }
}

enum BubbleItemLayout {
    static let sampleCounts = [0, 1, 2, 3, 6]
    static let maximumVisiblePreviews = 3
    static let contentCycleDuration: TimeInterval = 12

    static func visiblePreviewCount(for totalCount: Int) -> Int {
        min(max(totalCount, 0), maximumVisiblePreviews)
    }

    static func showsOverflowHint(for totalCount: Int) -> Bool {
        totalCount > maximumVisiblePreviews
    }

    static func placements(for totalCount: Int) -> [BubblePreviewPlacement] {
        return switch visiblePreviewCount(for: totalCount) {
        case 0:
            []
        case 1:
            [BubblePreviewPlacement(
                slot: 0, content: .stillLife,
                width: 0.43, height: 0.54, x: -0.06, y: 0.04,
                rotation: -4, opacity: 0.98, depth: 1, drift: 0.006
            )]
        case 2:
            [
                // B: two relaxed diagonals with the photo settled behind.
                BubblePreviewPlacement(
                    slot: 0, content: .stillLife,
                    width: 0.34, height: 0.41, x: -0.15, y: -0.05,
                    rotation: -9, opacity: 0.96, depth: 0, drift: 0.010
                ),
                BubblePreviewPlacement(
                    slot: 1, content: .document,
                    width: 0.34, height: 0.40, x: 0.14, y: 0.05,
                    rotation: 7, opacity: 0.88, depth: 1, drift: 0.010
                )
            ]
        default:
            [
                // Three unequal planes: a photo lead, with document and
                // diagram edges readable at upper and lower right.
                BubblePreviewPlacement(
                    slot: 0, content: .stillLife,
                    width: 0.40, height: 0.49, x: -0.11, y: 0.02,
                    rotation: -5, opacity: 0.98, depth: 2, drift: 0.006
                ),
                BubblePreviewPlacement(
                    slot: 1, content: .document,
                    width: 0.28, height: 0.37, x: 0.16, y: -0.09,
                    rotation: 6, opacity: 0.91, depth: 1, drift: 0.006
                ),
                BubblePreviewPlacement(
                    slot: 2, content: .diagram,
                    width: 0.22, height: 0.30, x: 0.11, y: 0.20,
                    rotation: 8, opacity: 0.94, depth: 0, drift: 0.006
                )
            ]
        }
    }

    static func contentPair(for placement: BubblePreviewPlacement, totalCount: Int) -> (front: BubbleDemoContent, back: BubbleDemoContent) {
        guard totalCount > maximumVisiblePreviews else {
            return (placement.content, placement.content)
        }
        let samples = BubbleDemoContent.allCases
        return (samples[placement.slot], samples[placement.slot + maximumVisiblePreviews])
    }

    static func crossfade(at time: TimeInterval) -> Double {
        let phase = (time.truncatingRemainder(dividingBy: contentCycleDuration)) / contentCycleDuration
        return 0.5 - 0.5 * cos(phase * 2 * .pi)
    }

    static func maximumVisualRadius(for placement: BubblePreviewPlacement, diameter: CGFloat) -> CGFloat {
        let halfWidth = diameter * placement.width * 0.5
        let halfHeight = diameter * placement.height * 0.5
        let radians = CGFloat(placement.rotation * .pi / 180)
        let extentX = abs(cos(radians)) * halfWidth + abs(sin(radians)) * halfHeight
        let extentY = abs(sin(radians)) * halfWidth + abs(cos(radians)) * halfHeight
        let motion = diameter * placement.drift
        let shadowMargin = max(1, min(4, diameter * 0.016)) + 0.5
        let x = abs(diameter * placement.x) + extentX + motion + shadowMargin
        let y = abs(diameter * placement.y) + extentY + motion + shadowMargin
        return hypot(x, y)
    }
}

struct BubbleContentPreviews: View {
    let totalCount: Int
    let time: TimeInterval
    let gather: CGFloat
    let bubbleDiameter: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let placements = BubbleItemLayout.placements(for: totalCount)

            ZStack {
                if BubbleItemLayout.showsOverflowHint(for: totalCount),
                   let document = placements.first(where: { $0.slot == 1 }) {
                    RearStackEdge(
                        width: diameter * document.width,
                        height: diameter * document.height,
                        shellDiameter: bubbleDiameter
                    )
                    .rotationEffect(.degrees(document.rotation))
                    .position(
                        x: geometry.size.width * 0.5 + diameter * document.x,
                        y: geometry.size.height * 0.5 + diameter * document.y
                    )
                    .zIndex(document.depth - 0.5)
                }

                ForEach(placements) { placement in
                    let contentPair = BubbleItemLayout.contentPair(for: placement, totalCount: totalCount)
                    let driftPhase = time * 0.24 + Double(placement.slot) * 1.73
                    let gatherScale: CGFloat = 1 - gather * 0.76
                    let x = diameter * placement.x * gatherScale
                        + CGFloat(sin(driftPhase)) * diameter * placement.drift
                    let y = diameter * placement.y * gatherScale
                        + CGFloat(cos(driftPhase * 0.83)) * diameter * placement.drift * 0.72

                    DemoContentCard(
                        front: contentPair.front,
                        back: contentPair.back,
                        crossfade: totalCount > BubbleItemLayout.maximumVisiblePreviews ? BubbleItemLayout.crossfade(at: time) : 0,
                        shellDiameter: bubbleDiameter
                    )
                    .frame(width: diameter * placement.width, height: diameter * placement.height)
                    .rotationEffect(.degrees(placement.rotation + sin(driftPhase) * Double(placement.drift * 34)))
                    .scaleEffect(1 + CGFloat(sin(driftPhase + 0.8)) * 0.006 + gather * 0.018)
                    .opacity(placement.opacity)
                    .shadow(
                        color: .black.opacity(placement.depth == 0 ? 0.20 : 0.30),
                        radius: max(1, min(4, bubbleDiameter * 0.016)),
                        y: bubbleDiameter < 96 ? 0.5 : 2
                    )
                    .position(x: geometry.size.width * 0.5 + x, y: geometry.size.height * 0.5 + y)
                    .zIndex(placement.depth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("内置演示预览内容")
    }
}

private struct DemoContentCard: View {
    let front: BubbleDemoContent
    let back: BubbleDemoContent
    let crossfade: Double
    let shellDiameter: CGFloat

    private var isCompact: Bool { shellDiameter < 96 }
    private var cornerRadius: CGFloat { max(4, shellDiameter * 0.035) }

    var body: some View {
        ZStack {
            DemoContentArtwork(content: front, isCompact: isCompact)
                .opacity(1 - crossfade)
            if back != front {
                DemoContentArtwork(content: back, isCompact: isCompact)
                    .opacity(crossfade)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(front == .stillLife || front == .stillLifeDetail ? 0.78 : 0.68), lineWidth: max(0.6, shellDiameter * 0.004))
        }
    }
}

private struct DemoContentArtwork: View {
    let content: BubbleDemoContent
    let isCompact: Bool

    var body: some View {
        Group {
            switch content {
            case .stillLife:
                photo(detail: false)
            case .stillLifeDetail:
                photo(detail: true)
            case .document:
                DocumentPreview(isCompact: isCompact)
            case .diagram:
                DiagramPreview(isCompact: isCompact)
            case .report:
                ReportPreview(isCompact: isCompact)
            case .fieldNotes:
                FieldNotesPreview(isCompact: isCompact)
            }
        }
    }

    @ViewBuilder
    private func photo(detail: Bool) -> some View {
        if let image = DemoArtwork.stillLife {
            GeometryReader { geometry in
                let scale: CGFloat = detail ? 1.60 : 1
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width * scale, height: geometry.size.height * scale, alignment: detail ? .bottomTrailing : .center)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: detail ? .bottomTrailing : .center)
                    .clipped()
            }
        } else {
            Color.clear
        }
    }
}

private struct DocumentPreview: View {
    let isCompact: Bool

    private let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
    private let ink = Color(red: 0.16, green: 0.23, blue: 0.28)
    private let moss = Color(red: 0.35, green: 0.47, blue: 0.38)

    var body: some View {
        GeometryReader { geometry in
            let inset = max(3, geometry.size.width * 0.085)
            VStack(alignment: .leading, spacing: isCompact ? 3 : max(3, geometry.size.height * 0.035)) {
                HStack(spacing: 3) {
                    Capsule().fill(moss).frame(width: max(8, geometry.size.width * 0.18), height: max(1.6, geometry.size.height * 0.018))
                    if !isCompact {
                        Text("STUDIO NOTES")
                            .font(.system(size: max(5, geometry.size.width * 0.055), weight: .semibold, design: .rounded))
                            .tracking(0.65)
                            .foregroundStyle(moss)
                            .lineLimit(1)
                    }
                }
                if isCompact {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.73, green: 0.79, blue: 0.69)).frame(height: geometry.size.height * 0.20)
                    DocumentLines(ink: ink)
                } else {
                    Text("光线与安静")
                        .font(.system(size: max(8, geometry.size.width * 0.105), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text("窗边的光线在桌面缓慢移动，让共享空间安静下来。")
                        .font(.system(size: max(5.5, geometry.size.width * 0.054), weight: .regular, design: .serif))
                        .foregroundStyle(ink.opacity(0.78))
                        .lineSpacing(1)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 1)
                    HStack(alignment: .bottom, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.73, green: 0.79, blue: 0.69)).frame(height: geometry.size.height * 0.17)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.84, green: 0.68, blue: 0.51)).frame(height: geometry.size.height * 0.27)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.52, green: 0.64, blue: 0.67)).frame(height: geometry.size.height * 0.21)
                        RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.88, green: 0.82, blue: 0.67)).frame(height: geometry.size.height * 0.34)
                    }
                    .frame(height: geometry.size.height * 0.37, alignment: .bottom)
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(paper)
        }
    }
}

private struct DiagramPreview: View {
    let isCompact: Bool

    private let backdrop = Color(red: 0.89, green: 0.94, blue: 0.93)
    private let ink = Color(red: 0.17, green: 0.30, blue: 0.34)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                backdrop
                if !isCompact {
                    Text("FLOW MAP")
                        .font(.system(size: max(6, geometry.size.width * 0.075), weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(ink)
                        .padding(geometry.size.width * 0.09)
                }
                Canvas { context, size in
                    let nodes = [
                        CGPoint(x: size.width * 0.27, y: size.height * 0.42),
                        CGPoint(x: size.width * 0.69, y: size.height * 0.28),
                        CGPoint(x: size.width * 0.66, y: size.height * 0.70)
                    ]
                    var links = Path()
                    links.move(to: nodes[0]); links.addLine(to: nodes[1])
                    links.move(to: nodes[0]); links.addLine(to: nodes[2])
                    links.move(to: nodes[1]); links.addLine(to: nodes[2])
                    context.stroke(links, with: .color(ink.opacity(0.54)), style: StrokeStyle(lineWidth: max(1.2, size.width * 0.018), lineCap: .round))
                    let colors = [Color(red: 0.29, green: 0.53, blue: 0.48), Color(red: 0.86, green: 0.61, blue: 0.38), Color(red: 0.45, green: 0.58, blue: 0.72)]
                    for (point, color) in zip(nodes, colors) {
                        let diameter = max(6, size.width * 0.10)
                        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
                        context.fill(Path(roundedRect: rect, cornerRadius: diameter * 0.28), with: .color(color))
                        context.stroke(Path(roundedRect: rect, cornerRadius: diameter * 0.28), with: .color(.white.opacity(0.85)), lineWidth: 1)
                    }
                }
                .padding(.horizontal, geometry.size.width * 0.08)
                .padding(.top, isCompact ? geometry.size.height * 0.08 : geometry.size.height * 0.24)
                if !isCompact {
                    DocumentLines(ink: ink.opacity(0.46))
                        .padding(.horizontal, geometry.size.width * 0.10)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, geometry.size.height * 0.09)
                }
            }
        }
    }
}

private struct ReportPreview: View {
    let isCompact: Bool

    private let paper = Color(red: 0.95, green: 0.92, blue: 0.84)
    private let ink = Color(red: 0.25, green: 0.31, blue: 0.34)
    private let tones = [Color(red: 0.40, green: 0.61, blue: 0.57), Color(red: 0.78, green: 0.54, blue: 0.36), Color(red: 0.43, green: 0.56, blue: 0.72), Color(red: 0.68, green: 0.70, blue: 0.48)]

    var body: some View {
        GeometryReader { geometry in
            let barHeights: [CGFloat] = [0.46, 0.68, 0.40, 0.82, 0.58]
            VStack(alignment: .leading, spacing: max(3, geometry.size.height * 0.06)) {
                if !isCompact {
                    Text("FIELD REPORT")
                        .font(.system(size: max(6, geometry.size.width * 0.075), weight: .semibold, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(ink.opacity(0.75))
                    Text("Seasonal observations")
                        .font(.system(size: max(7, geometry.size.width * 0.09), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                } else {
                    Capsule().fill(ink.opacity(0.54)).frame(width: geometry.size.width * 0.44, height: 1.5)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: geometry.size.width * 0.045) {
                    ForEach(tones.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tones[index])
                            .frame(height: geometry.size.height * barHeights[index])
                    }
                }
                .frame(height: geometry.size.height * 0.46, alignment: .bottom)
                if !isCompact {
                    DocumentLines(ink: ink.opacity(0.42))
                }
            }
            .padding(geometry.size.width * 0.10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paper)
        }
    }
}

private struct FieldNotesPreview: View {
    let isCompact: Bool

    private let paper = Color(red: 0.92, green: 0.94, blue: 0.87)
    private let ink = Color(red: 0.22, green: 0.34, blue: 0.29)

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: geometry.size.height * 0.07) {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.04)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.56, green: 0.69, blue: 0.57), Color(red: 0.83, green: 0.78, blue: 0.61)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: geometry.size.height * (isCompact ? 0.46 : 0.35))
                    .overlay(alignment: .bottomLeading) {
                        if !isCompact {
                            Capsule().fill(.white.opacity(0.75)).frame(width: geometry.size.width * 0.22, height: 2).padding(geometry.size.width * 0.08)
                        }
                    }
                if !isCompact {
                    Text("Field notes")
                        .font(.system(size: max(7, geometry.size.width * 0.095), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                    Text("A quiet record of color, shape, and light.")
                        .font(.system(size: max(5.5, geometry.size.width * 0.053), design: .serif))
                        .foregroundStyle(ink.opacity(0.72))
                        .lineLimit(2)
                } else {
                    DocumentLines(ink: ink.opacity(0.38))
                }
                Spacer(minLength: 0)
            }
            .padding(geometry.size.width * 0.10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paper)
        }
    }
}

private struct DocumentLines: View {
    let ink: Color

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 2) {
                Capsule().fill(ink.opacity(0.46)).frame(width: geometry.size.width * 0.76, height: 1.6)
                Capsule().fill(ink.opacity(0.28)).frame(width: geometry.size.width * 0.59, height: 1.3)
                Capsule().fill(ink.opacity(0.20)).frame(width: geometry.size.width * 0.68, height: 1.2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 7)
    }
}

private struct RearStackEdge: View {
    let width: CGFloat
    let height: CGFloat
    let shellDiameter: CGFloat

    private var step: CGFloat { max(1.7, shellDiameter * 0.016) }
    private var radius: CGFloat { max(3, shellDiameter * 0.035) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(red: 0.84, green: 0.87, blue: 0.85).opacity(0.84))
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.72), lineWidth: 0.65) }
                .offset(x: -step * 1.8, y: step * 1.8)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(red: 0.78, green: 0.82, blue: 0.82).opacity(0.88))
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.74), lineWidth: 0.65) }
                .offset(x: -step * 0.9, y: step * 0.9)
        }
        .frame(width: width, height: height)
    }
}

enum DemoArtwork {
    static let stillLife: NSImage? = {
        guard let url = Bundle.main.url(forResource: "DemoStillLife", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    static var isAvailable: Bool { stillLife != nil }
}

struct BubbleCountComparisonScene: View {
    static let size = CGSize(width: 960, height: 252)
    static let columnWidth: CGFloat = 180
    static let counts = BubbleItemLayout.sampleCounts

    let time: TimeInterval
    let light: SIMD2<Float>
    let arrival: ArrivalFrame

    var body: some View {
        ZStack {
            Backdrop(style: .night)
            HStack(spacing: 9) {
                ForEach(Self.counts, id: \.self) { count in
                    VStack(spacing: 3) {
                        Text(Self.title(for: count))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                        BubbleScene(
                            time: time,
                            light: light,
                            itemCount: count,
                            arrival: arrival,
                            canvasSize: CGSize(width: Self.columnWidth, height: 222),
                            bubbleDiameter: 164,
                            drawBackdrop: false
                        )
                    }
                    .frame(width: Self.columnWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static func title(for count: Int) -> String {
        count == 0 ? "0 · 空" : "\(count) · 内置示例"
    }
}
