import AppKit
import SwiftUI

enum BubbleComposition: String, CaseIterable, Hashable, Identifiable {
    case insetPair
    case floatingPair
    case softStack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .insetPair: "A·轻叠"
        case .floatingPair: "B·浮游"
        case .softStack: "C·柔藏"
        }
    }

    var placements: [BubblePreviewPlacement] {
        switch self {
        case .insetPair:
            [
                BubblePreviewPlacement(content: .document, width: 0.39, height: 0.53, x: 0.16, y: -0.05, rotation: 8, opacity: 0.70, depth: 0, drift: 0.010),
                BubblePreviewPlacement(content: .photo, width: 0.43, height: 0.54, x: -0.12, y: 0.05, rotation: -7, opacity: 0.96, depth: 1, drift: 0.010)
            ]
        case .floatingPair:
            [
                BubblePreviewPlacement(content: .document, width: 0.35, height: 0.47, x: 0.17, y: 0.08, rotation: 7, opacity: 0.82, depth: 1, drift: 0.022),
                BubblePreviewPlacement(content: .photo, width: 0.37, height: 0.45, x: -0.18, y: -0.07, rotation: -9, opacity: 0.88, depth: 0, drift: 0.022)
            ]
        case .softStack:
            [
                BubblePreviewPlacement(content: .photo, width: 0.39, height: 0.47, x: -0.035, y: 0.11, rotation: -3, opacity: 0.88, depth: 0, drift: 0.007),
                BubblePreviewPlacement(content: .document, width: 0.40, height: 0.54, x: 0.07, y: -0.04, rotation: 3, opacity: 0.68, depth: 1, drift: 0.007)
            ]
        }
    }

    var previewCount: Int { placements.count }
}

enum BubbleDemoContent: String, CaseIterable, Hashable, Identifiable {
    case photo
    case document

    var id: String { rawValue }
}

struct BubblePreviewPlacement: Identifiable {
    let content: BubbleDemoContent
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let opacity: Double
    let depth: Double
    let drift: CGFloat

    var id: String { content.id }
}

struct BubbleContentPreviews: View {
    let composition: BubbleComposition
    let time: TimeInterval
    let gather: CGFloat
    let bubbleDiameter: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let crossfade = 0.5 + 0.5 * sin(time * 0.38)

            ZStack {
                ForEach(composition.placements) { placement in
                    let focus = placement.content == .photo ? crossfade : 1 - crossfade
                    let driftPhase = time * 0.24 + (placement.content == .photo ? 0.4 : 2.2)
                    let gatherScale = 1 - Double(gather) * 0.76
                    let x = diameter * placement.x * gatherScale
                        + CGFloat(sin(driftPhase)) * diameter * placement.drift
                    let y = diameter * placement.y * gatherScale
                        + CGFloat(cos(driftPhase * 0.83)) * diameter * placement.drift * 0.72

                    DemoContentCard(content: placement.content, shellDiameter: bubbleDiameter)
                        .frame(width: diameter * placement.width, height: diameter * placement.height)
                        .rotationEffect(.degrees(placement.rotation + sin(driftPhase) * Double(placement.drift * 42)))
                        .scaleEffect(1 + CGFloat(sin(driftPhase + 0.8)) * 0.008 + gather * 0.018)
                        .opacity(placement.opacity * (0.60 + 0.40 * focus))
                        .shadow(color: .black.opacity(placement.depth == 0 ? 0.20 : 0.32), radius: placement.depth == 0 ? 2 : 5, y: placement.depth == 0 ? 1 : 3)
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
    let content: BubbleDemoContent
    let shellDiameter: CGFloat

    private var isCompact: Bool { shellDiameter < 96 }
    private var cornerRadius: CGFloat { max(4, shellDiameter * 0.035) }

    var body: some View {
        Group {
            switch content {
            case .photo:
                photoCrop
            case .document:
                DocumentPageCrop(isCompact: isCompact)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(content == .photo ? 0.76 : 0.68), lineWidth: max(0.6, shellDiameter * 0.004))
        }
    }

    @ViewBuilder
    private var photoCrop: some View {
        if let stillLife = DemoArtwork.stillLife {
            Image(nsImage: stillLife)
                .resizable()
                .scaledToFill()
        } else {
            Color.clear
        }
    }
}

private struct DocumentPageCrop: View {
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
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.73, green: 0.79, blue: 0.69))
                        .frame(height: geometry.size.height * 0.20)
                    VStack(alignment: .leading, spacing: 2) {
                        Capsule().fill(ink.opacity(0.44)).frame(width: geometry.size.width * 0.70, height: 1.4)
                        Capsule().fill(ink.opacity(0.23)).frame(width: geometry.size.width * 0.52, height: 1.2)
                    }
                } else {
                    Text("光线与安静")
                        .font(.system(size: max(8, geometry.size.width * 0.105), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

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
        .overlay {
            RoundedRectangle(cornerRadius: 1).strokeBorder(.white.opacity(0.84), lineWidth: 0.7)
        }
    }
}

enum DemoArtwork {
    static let stillLife: NSImage? = {
        guard let url = Bundle.main.url(forResource: "DemoStillLife", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    static var isAvailable: Bool { stillLife != nil }
}

struct BubbleVariantComparisonScene: View {
    static let size = CGSize(width: 512, height: 204)

    let time: TimeInterval
    let light: SIMD2<Float>
    let arrival: ArrivalFrame

    var body: some View {
        ZStack {
            Backdrop(style: .night)
            HStack(spacing: 4) {
                ForEach(BubbleComposition.allCases) { composition in
                    VStack(spacing: 3) {
                        Text(composition.label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))

                        BubbleScene(
                            time: time,
                            light: light,
                            populated: true,
                            arrival: arrival,
                            canvasSize: CGSize(width: 164, height: 176),
                            bubbleDiameter: 148,
                            drawBackdrop: false,
                            composition: composition
                        )
                    }
                    .frame(width: 164)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
