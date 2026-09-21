import AppKit
import SwiftUI

enum NotchDemoPresentation: String, CaseIterable, Identifiable, Equatable {
    case widget
    case dualWing
    case minimal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .widget: return "小组件"
        case .dualWing: return "左右翼"
        case .minimal: return "极简"
        }
    }
    var iconSize: CGFloat { self == .minimal ? 14 : 20 }
}

enum NotchDemoState: CaseIterable, Identifiable, Equatable {
    case receivingEmpty
    case receivingPopulated
    case pausedEmpty
    case pausedPopulated

    var id: String { String(describing: self) }
    var isArmed: Bool { self == .receivingEmpty || self == .receivingPopulated }
    var itemCount: Int { self == .receivingPopulated || self == .pausedPopulated ? 3 : 0 }
    var title: String {
        switch self {
        case .receivingEmpty: return "等待接收 · 空"
        case .receivingPopulated: return "等待接收 · 有内容"
        case .pausedEmpty: return "暂停接收 · 空"
        case .pausedPopulated: return "暂停接收 · 有内容"
        }
    }
    var shortStatus: String {
        switch self {
        case .receivingEmpty, .receivingPopulated: return "等待接收"
        case .pausedEmpty, .pausedPopulated: return "暂停接收"
        }
    }
}

enum NotchSignalMotion {
    static let cycleDuration: TimeInterval = 8
    static let radialFraction: CGFloat = 0.375
    static let maximumBarFraction: CGFloat = 0.23

    /// One short tangent makes a slow orbit just inside the closed front shell.
    /// It never leaves a trail or lights the rest of the ring.
    static func angle(at time: TimeInterval) -> Double {
        let cycle = ((time.truncatingRemainder(dividingBy: cycleDuration)) + cycleDuration)
            .truncatingRemainder(dividingBy: cycleDuration)
        return -.pi / 2 + 2 * .pi * cycle / cycleDuration
    }

    static func normalizedProgress(at time: TimeInterval) -> Double {
        let cycle = ((time.truncatingRemainder(dividingBy: cycleDuration)) + cycleDuration)
            .truncatingRemainder(dividingBy: cycleDuration)
        return cycle / cycleDuration
    }
}

struct NotchPreviewGlyph: View {
    let size: CGFloat
    let itemCount: Int
    let isArmed: Bool
    let time: TimeInterval

    private var frontDiameter: CGFloat { size * 24 / 28 }
    private var frontCenter: CGPoint {
        CGPoint(x: size * 0.5 - size * 1.5 / 28, y: size * 0.5 + size * 1.5 / 28)
    }

    var body: some View {
        ZStack {
            if itemCount > 0 {
                MiniPreviewStack(itemCount: itemCount)
                    .frame(width: frontDiameter, height: frontDiameter)
                    .clipShape(Circle())
                    .position(frontCenter)
            }

            DoubleBubbleMark(size: size)

            if isArmed {
                CurvedReceiveGlint(size: frontDiameter, time: time)
                    .frame(width: frontDiameter, height: frontDiameter)
                    .clipShape(Circle())
                    .position(frontCenter)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(itemCount == 0 ? "空泡泡" : "含内置预览的泡泡")
    }
}

private struct CurvedReceiveGlint: View {
    let size: CGFloat
    let time: TimeInterval

    private var angle: Double { NotchSignalMotion.angle(at: time) }
    private var center: CGPoint {
        let radius = size * NotchSignalMotion.radialFraction
        return CGPoint(
            x: size * 0.5 + CGFloat(cos(angle)) * radius,
            y: size * 0.5 + CGFloat(sin(angle)) * radius
        )
    }
    private var barLength: CGFloat {
        size * NotchSignalMotion.maximumBarFraction * CGFloat(0.88 + 0.12 * (0.5 + 0.5 * cos(angle)))
    }
    private var barThickness: CGFloat { max(0.48, size * (0.045 + 0.010 * CGFloat(0.5 + 0.5 * sin(angle)))) }
    private var glow: Double { 0.52 + 0.28 * (0.5 + 0.5 * sin(angle + .pi / 3)) }

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [
                    Color.white.opacity(glow * 0.34),
                    Color(red: 0.84, green: 0.95, blue: 1).opacity(glow),
                    Color(red: 1, green: 0.91, blue: 0.82).opacity(glow * 0.70)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: barLength, height: barThickness)
            .rotationEffect(.radians(angle + .pi / 2))
            .shadow(color: Color(red: 0.80, green: 0.92, blue: 1).opacity(glow * 0.50), radius: max(0.25, size * 0.07))
            .position(center)
    }
}

private struct MiniPreviewStack: View {
    let itemCount: Int

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(BubbleItemLayout.placements(for: itemCount)) { placement in
                    MiniPreviewCard(content: placement.content)
                        .frame(width: diameter * placement.width, height: diameter * placement.height)
                        .rotationEffect(.degrees(placement.rotation))
                        .opacity(placement.opacity)
                        .blur(radius: placement.blur * diameter)
                        .position(
                            x: geometry.size.width * (0.5 + placement.x),
                            y: geometry.size.height * (0.5 + placement.y)
                        )
                        .zIndex(placement.depth)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Tiny planes use the same bundled artwork identities as the large bubble,
/// reduced to color, crop, and a few native document/chart marks.
private struct MiniPreviewCard: View {
    let content: BubbleDemoContent

    private var paper: Color {
        switch content {
        case .stillLife, .stillLifeDetail: return Color(red: 0.34, green: 0.42, blue: 0.44)
        case .document: return Color(red: 0.95, green: 0.92, blue: 0.84)
        case .diagram: return Color(red: 0.78, green: 0.88, blue: 0.85)
        case .report: return Color(red: 0.92, green: 0.87, blue: 0.76)
        case .fieldNotes: return Color(red: 0.80, green: 0.86, blue: 0.75)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                paper
                if content == .stillLife || content == .stillLifeDetail {
                    if let image = DemoArtwork.stillLife {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                } else {
                    Canvas { context, size in
                        let ink = Color(red: 0.19, green: 0.30, blue: 0.31).opacity(0.65)
                        if content == .diagram {
                            var links = Path()
                            links.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.55))
                            links.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.32))
                            links.addLine(to: CGPoint(x: size.width * 0.67, y: size.height * 0.75))
                            context.stroke(links, with: .color(ink), lineWidth: max(0.35, size.width * 0.035))
                            for (point, color) in [
                                (CGPoint(x: size.width * 0.25, y: size.height * 0.55), Color(red: 0.31, green: 0.55, blue: 0.49)),
                                (CGPoint(x: size.width * 0.72, y: size.height * 0.32), Color(red: 0.85, green: 0.59, blue: 0.37)),
                                (CGPoint(x: size.width * 0.67, y: size.height * 0.75), Color(red: 0.43, green: 0.58, blue: 0.70))
                            ] {
                                let diameter = max(0.8, size.width * 0.13)
                                let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
                                context.fill(Path(ellipseIn: rect), with: .color(color))
                            }
                        } else {
                            let line = CGRect(x: size.width * 0.13, y: size.height * 0.20, width: size.width * 0.48, height: max(0.45, size.height * 0.055))
                            context.fill(Path(roundedRect: line, cornerRadius: 1), with: .color(ink))
                            let heights: [CGFloat] = content == .fieldNotes ? [0.26, 0.43, 0.32] : [0.28, 0.48, 0.36]
                            let colors = [Color(red: 0.41, green: 0.61, blue: 0.56), Color(red: 0.81, green: 0.57, blue: 0.38), Color(red: 0.46, green: 0.59, blue: 0.71)]
                            for index in heights.indices {
                                let width = size.width * 0.15
                                let rect = CGRect(
                                    x: size.width * (0.18 + CGFloat(index) * 0.25),
                                    y: size.height * (0.83 - heights[index]),
                                    width: width,
                                    height: size.height * heights[index]
                                )
                                context.fill(Path(roundedRect: rect, cornerRadius: max(0.35, width * 0.12)), with: .color(colors[index]))
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: max(0.55, min(2.2, min(geometry.size.width, geometry.size.height) * 0.13)), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: max(0.55, min(2.2, min(geometry.size.width, geometry.size.height) * 0.13)), style: .continuous)
                    .strokeBorder(.white.opacity(0.84), lineWidth: 0.42)
            }
        }
    }
}

struct NotchAppearanceBoard: View {
    static let size = CGSize(width: 1040, height: 558)
    static let movieScale: CGFloat = 0.84
    static let movieSize = CGSize(width: size.width * movieScale, height: size.height * movieScale)

    let time: TimeInterval
    var presentationScale: CGFloat = 1

    private let rowLabelWidth: CGFloat = 86
    private let cellWidth: CGFloat = 224

    var body: some View {
        ZStack {
            Backdrop(style: .night)
            VStack(spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("QuotaNotch · 接收状态")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.93))
                    Spacer()
                    Text("内置示例预览 · 有内容固定展示三张")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }
                HStack(spacing: 8) {
                    Color.clear.frame(width: rowLabelWidth, height: 1)
                    ForEach(NotchDemoState.allCases) { state in
                        Text(state.title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.73))
                            .frame(width: cellWidth)
                    }
                }

                ForEach(NotchDemoPresentation.allCases) { presentation in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                            Text("图标 \(Int(presentation.iconSize)) pt")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .frame(width: rowLabelWidth, alignment: .leading)

                        ForEach(NotchDemoState.allCases) { state in
                            NotchAppearanceCell(presentation: presentation, state: state, time: time)
                                .frame(width: cellWidth, height: 145)
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(presentationScale)
        .frame(width: Self.size.width * presentationScale, height: Self.size.height * presentationScale)
    }
}

private struct NotchAppearanceCell: View {
    let presentation: NotchDemoPresentation
    let state: NotchDemoState
    let time: TimeInterval

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                NotchPreviewGlyph(size: 54, itemCount: state.itemCount, isArmed: state.isArmed, time: time)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.shortStatus)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(state.itemCount == 0 ? "暂无预览" : "图片 · 文档 · 图表")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            NotchHardwareSample(presentation: presentation, state: state, time: time)
        }
        .padding(8)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.075), lineWidth: 0.8)
        }
    }
}

private struct NotchHardwareSample: View {
    let presentation: NotchDemoPresentation
    let state: NotchDemoState
    let time: TimeInterval
    var itemCount: Int? = nil

    private var displayedCount: Int { itemCount ?? state.itemCount }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.96))

            HStack(spacing: 0) {
                Group {
                    if presentation == .minimal {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.40))
                            Rectangle().fill(.white.opacity(0.22)).frame(width: 0.7, height: 16)
                            NotchPreviewGlyph(size: 14, itemCount: displayedCount, isArmed: state.isArmed, time: time)
                                .frame(width: 16, height: 18)
                        }
                    } else {
                        NotchPreviewGlyph(size: 20, itemCount: displayedCount, isArmed: state.isArmed, time: time)
                    }
                }
                .frame(width: 68, height: 40, alignment: .leading)

                Spacer(minLength: 0)

                if presentation == .dualWing {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.shortStatus)
                            .font(.system(size: 7, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(displayedCount == 0 ? "暂无预览" : "已有内容")
                            .font(.system(size: 6, weight: .regular, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .frame(width: 68, height: 40, alignment: .leading)
                } else {
                    Color.clear.frame(width: 68, height: 40)
                }
            }
            .padding(.horizontal, 5)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black)
                .frame(width: 54, height: 43)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.075), lineWidth: 0.7)
                }
        }
        .frame(width: 202, height: 48)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 0.8)
        }
        .accessibilityLabel("分离的左右 notch 翼与中央缺口")
    }
}

struct NotchContentCountBoard: View {
    static let size = CGSize(width: 1040, height: 480)
    static let counts = BubbleItemLayout.sampleCounts

    let time: TimeInterval

    var body: some View {
        ZStack {
            Backdrop(style: .night)
            VStack(spacing: 8) {
                HStack {
                    Text("内容数量与 notch 尺寸")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.93))
                    Spacer()
                    Text("仅为内置演示 · 数量标签在图标之外")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }

                HStack(spacing: 7) {
                    Color.clear.frame(width: 66, height: 1)
                    ForEach(NotchDemoPresentation.allCases) { presentation in
                        VStack(spacing: 3) {
                            Text(presentation.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.80))
                            Text("图标 \(Int(presentation.iconSize)) pt")
                                .font(.system(size: 8, design: .rounded))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Self.counts, id: \.self) { count in
                    HStack(spacing: 7) {
                        Text(count == 0 ? "空" : "\(count) 项")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 66, alignment: .leading)
                        ForEach(NotchDemoPresentation.allCases) { presentation in
                            HStack(spacing: 11) {
                                NotchPreviewGlyph(size: 52, itemCount: count, isArmed: true, time: time)
                                NotchHardwareSample(
                                    presentation: presentation,
                                    state: count == 0 ? .receivingEmpty : .receivingPopulated,
                                    time: time,
                                    itemCount: count
                                )
                                .frame(maxWidth: .infinity)
                            }
                    .frame(maxWidth: .infinity, minHeight: 70)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

struct NotchSignalProof: View {
    let armed: Bool
    let itemCount: Int
    let time: TimeInterval

    var body: some View {
        ZStack {
            Backdrop(style: .night)
            NotchPreviewGlyph(size: 144, itemCount: itemCount, isArmed: armed, time: time)
        }
        .frame(width: 256, height: 256)
    }
}
