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
    static let cycleDuration: TimeInterval = 4
    static let orbitRadiusFraction: CGFloat = 0.37
    static let arcSpan: Double = 0.96

    private static func phase(at time: TimeInterval) -> Double {
        let turns = time / cycleDuration
        return turns - floor(turns)
    }

    /// The short inner arc slows near the top, swishes fastest through the bottom,
    /// then eases back up without reversing or leaving a trail.
    static func angle(at time: TimeInterval) -> Double {
        let turns = time / cycleDuration
        let phaseAngle = 2 * .pi * phase(at: time)
        return -.pi / 2 + 2 * .pi * turns - 0.70 * sin(phaseAngle)
    }

    static func speed(at time: TimeInterval) -> Double {
        1 - 0.70 * cos(2 * .pi * phase(at: time))
    }

    static func normalizedProgress(at time: TimeInterval) -> Double {
        phase(at: time)
    }

    static func speedProgress(at time: TimeInterval) -> Double {
        (speed(at: time) - 0.30) / 1.40
    }
}

enum NotchBubbleGeometry {
    static let frontDiameterFraction: CGFloat = 0.78
    static let frontCenter = CGPoint(x: 0.59, y: 0.59)
    static let rearDiameterFraction: CGFloat = 0.54
    static let rearCenter = CGPoint(x: 0.34, y: 0.38)

    static func frontDiameter(for size: CGFloat) -> CGFloat { size * frontDiameterFraction }
    static func rearDiameter(for size: CGFloat) -> CGFloat { size * rearDiameterFraction }
    static func point(_ fraction: CGPoint, in size: CGFloat) -> CGPoint {
        CGPoint(x: fraction.x * size, y: fraction.y * size)
    }
    static func contourWidth(for size: CGFloat) -> CGFloat { max(0.42, size * 0.026) }
}

struct NotchRectanglePlacement: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let opacity: Double
    let depth: Double
}

enum NotchRectangleLayout {
    static let counts = [0, 1, 2, 3, 4]

    static func placements(for count: Int) -> [NotchRectanglePlacement] {
        switch min(max(count, 0), 4) {
        case 0:
            return []
        case 1:
            return [
                .init(id: 0, x: 0.48, y: 0.51, width: 0.34, height: 0.42, rotation: -4, opacity: 0.93, depth: 1)
            ]
        case 2:
            return [
                .init(id: 0, x: 0.43, y: 0.47, width: 0.29, height: 0.38, rotation: -7, opacity: 0.68, depth: 0),
                .init(id: 1, x: 0.57, y: 0.55, width: 0.29, height: 0.38, rotation: 5, opacity: 0.96, depth: 1)
            ]
        case 3:
            return [
                .init(id: 0, x: 0.43, y: 0.49, width: 0.30, height: 0.39, rotation: -5, opacity: 0.96, depth: 3),
                .init(id: 1, x: 0.60, y: 0.43, width: 0.24, height: 0.31, rotation: 5, opacity: 0.78, depth: 2),
                .init(id: 2, x: 0.57, y: 0.62, width: 0.23, height: 0.30, rotation: 8, opacity: 0.67, depth: 1)
            ]
        default:
            return [
                .init(id: 0, x: 0.48, y: 0.65, width: 0.21, height: 0.28, rotation: 2, opacity: 0.48, depth: 1),
                .init(id: 1, x: 0.58, y: 0.59, width: 0.225, height: 0.29, rotation: 8, opacity: 0.68, depth: 2),
                .init(id: 2, x: 0.60, y: 0.43, width: 0.235, height: 0.30, rotation: 5, opacity: 0.79, depth: 3),
                .init(id: 3, x: 0.43, y: 0.49, width: 0.28, height: 0.36, rotation: -5, opacity: 0.97, depth: 4)
            ]
        }
    }
}

struct NotchPreviewGlyph: View {
    let size: CGFloat
    let itemCount: Int
    let isArmed: Bool
    let time: TimeInterval

    private var frontDiameter: CGFloat { NotchBubbleGeometry.frontDiameter(for: size) }
    private var frontCenter: CGPoint { NotchBubbleGeometry.point(NotchBubbleGeometry.frontCenter, in: size) }
    private var rearDiameter: CGFloat { NotchBubbleGeometry.rearDiameter(for: size) }
    private var rearCenter: CGPoint { NotchBubbleGeometry.point(NotchBubbleGeometry.rearCenter, in: size) }
    private var contourWidth: CGFloat { NotchBubbleGeometry.contourWidth(for: size) }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .overlay(Circle().stroke(Color(white: 0.56).opacity(0.48), lineWidth: contourWidth * 0.88))
                .frame(width: rearDiameter, height: rearDiameter)
                .position(rearCenter)

            Circle()
                .fill(Color.black)
                .frame(width: frontDiameter, height: frontDiameter)
                .position(frontCenter)

            if itemCount > 0 {
                PlainRectangleStack(itemCount: itemCount)
                    .frame(width: frontDiameter, height: frontDiameter)
                    .clipShape(Circle())
                    .position(frontCenter)
            }

            if isArmed {
                CurvedReceiveGlint(size: frontDiameter, time: time)
                    .frame(width: frontDiameter, height: frontDiameter)
                    .clipShape(Circle())
                    .position(frontCenter)
            }

            Circle()
                .stroke(Color(white: 0.65).opacity(0.92), lineWidth: contourWidth)
                .frame(width: frontDiameter, height: frontDiameter)
                .position(frontCenter)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(itemCount == 0 ? "空的双轮廓气泡" : "\(itemCount) 个矩形预览")
    }
}

private struct CurvedReceiveGlint: View {
    let size: CGFloat
    let time: TimeInterval

    private var angle: Double { NotchSignalMotion.angle(at: time) }
    private var speedProgress: Double { NotchSignalMotion.speedProgress(at: time) }
    private var lineWidth: CGFloat { max(0.46, size * 0.026) }
    private var brightness: Double { 0.62 + 0.28 * speedProgress }
    private var haloRadius: CGFloat { max(0.45, size * 0.025) }

    var body: some View {
        InnerReceiveArc(
            angle: angle,
            span: NotchSignalMotion.arcSpan,
            radiusFraction: NotchSignalMotion.orbitRadiusFraction
        )
        .stroke(
            Color.white.opacity(brightness),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .shadow(color: .white.opacity(0.20 + 0.24 * speedProgress), radius: haloRadius)
    }
}

private struct InnerReceiveArc: Shape {
    var angle: Double
    var span: Double
    var radiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let radius = diameter * radiusFraction
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(angle - span * 0.5),
            endAngle: .radians(angle + span * 0.5),
            clockwise: false
        )
        return path
    }
}

private struct PlainRectangleStack: View {
    let itemCount: Int

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(NotchRectangleLayout.placements(for: itemCount)) { placement in
                    RoundedRectangle(cornerRadius: max(0.35, diameter * 0.018), style: .continuous)
                        .fill(Color(white: 0.78).opacity(placement.opacity))
                        .overlay {
                            RoundedRectangle(cornerRadius: max(0.35, diameter * 0.018), style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: max(0.30, diameter * 0.008))
                        }
                        .frame(width: diameter * placement.width, height: diameter * placement.height)
                        .rotationEffect(.degrees(placement.rotation))
                        .position(x: geometry.size.width * placement.x, y: geometry.size.height * placement.y)
                        .zIndex(placement.depth)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    Text("双层空心气泡 · 内侧短弧缓速旋转")
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
                    Text(state.itemCount == 0 ? "暂无预览" : "简化矩形预览")
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
    static let counts = NotchRectangleLayout.counts

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
                    Text("仅显示中性矩形 · 数量标注在图标之外")
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
