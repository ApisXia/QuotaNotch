// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct BubbleNotchRectangle: Equatable, Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    let rotation: Double
    let opacity: Double
    let depth: Double
}

/// Shared, content-free page silhouettes for the shelf mark. Coordinates use one square
/// source plane in every size so Minimal never distorts the file stack.
enum BubbleNotchLayout {
    static let supportedCounts = 0...4
    static let minimalWidth: CGFloat = 16
    static let minimalFilesHeight: CGFloat = 10
    static let minimalGap: CGFloat = 2
    static let minimalBubbleDiameter: CGFloat = 14
    static let minimalTotalHeight: CGFloat = minimalFilesHeight + minimalGap + minimalBubbleDiameter

    static func rectangles(for count: Int) -> [BubbleNotchRectangle] {
        switch min(max(count, 0), 4) {
        case 0:
            return []
        case 1:
            return [.init(id: 0, x: 0.48, y: 0.51, width: 0.34, height: 0.42, rotation: -4, opacity: 0.93, depth: 1)]
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

    static func visibleCount(for itemCount: Int) -> Int { min(max(itemCount, 0), 4) }
    static func shouldShowClosedGlyph(hasConfiguredReceiving: Bool, itemCount: Int) -> Bool {
        hasConfiguredReceiving || itemCount > 0
    }
    static func addedLeftFootprint(widgetWidth: CGFloat, hasExistingLeftModule: Bool) -> CGFloat {
        guard widgetWidth > 0 else { return 0 }
        return hasExistingLeftModule ? 16 + 10 : widgetWidth
    }
    static func centerCorrection(leftAdded: CGFloat, rightAdded: CGFloat = 0) -> CGFloat {
        (rightAdded - leftAdded) / 2
    }
    static func minimalScale(closedHeight: CGFloat, margin: CGFloat = 2) -> CGFloat {
        guard closedHeight > margin, minimalTotalHeight > 0 else { return 0 }
        return min(1, max(0, closedHeight - margin) / minimalTotalHeight)
    }

    static func minimalPlacements(for count: Int, width: CGFloat = minimalWidth,
                                  height: CGFloat = minimalFilesHeight) -> [BubbleNotchRectangle] {
        let placements = rectangles(for: count)
        let bounds = rotatedBounds(of: placements)
        guard !placements.isEmpty, bounds.width > 0, bounds.height > 0, width > 0, height > 0 else { return [] }
        let scale = min(width * 0.92 / bounds.width, height * 0.84 / bounds.height)
        let center = CGPoint(x: width * 0.5 + (0.5 - bounds.midX) * scale,
                             y: height * 0.5 + (0.5 - bounds.midY) * scale)
        return placements.map { item in
            var fitted = item
            fitted.x = center.x + (item.x - 0.5) * scale
            fitted.y = center.y + (item.y - 0.5) * scale
            fitted.width = item.width * scale
            fitted.height = item.height * scale
            return fitted
        }
    }

    static func rotatedBounds(of placements: [BubbleNotchRectangle]) -> CGRect {
        placements.reduce(into: CGRect.null) { result, item in
            let radians = CGFloat(item.rotation * .pi / 180)
            let extentX = abs(cos(radians)) * item.width * 0.5 + abs(sin(radians)) * item.height * 0.5
            let extentY = abs(sin(radians)) * item.width * 0.5 + abs(cos(radians)) * item.height * 0.5
            result = result.union(CGRect(x: item.x - extentX, y: item.y - extentY,
                                         width: extentX * 2, height: extentY * 2))
        }
    }
}

enum BubbleReceiveMotion {
    static let cycleDuration: TimeInterval = 4
    static let arcSpan: Double = 0.96
    static let orbitRadiusFraction: CGFloat = 0.37
    private static let slowZoneWeight = 1.18
    private static let returnEaseWeight = 0.25
    static let minimumSpeed = 0.07
    static let maximumSpeed = 2.43

    private static func phase(_ time: TimeInterval) -> Double {
        let turns = time / cycleDuration
        return turns - floor(turns)
    }

    static func angle(at time: TimeInterval) -> Double {
        let turns = time / cycleDuration
        let phaseAngle = 2 * Double.pi * phase(time)
        let weightedTurns = turns
            - slowZoneWeight / (2 * Double.pi) * sin(phaseAngle)
            + returnEaseWeight / (4 * Double.pi) * sin(2 * phaseAngle)
        return -3 * Double.pi / 4 + 2 * Double.pi * weightedTurns
    }

    static func speed(at time: TimeInterval) -> Double {
        let phaseAngle = 2 * Double.pi * phase(time)
        return 1 - slowZoneWeight * cos(phaseAngle) + returnEaseWeight * cos(2 * phaseAngle)
    }

    static func speedProgress(at time: TimeInterval) -> Double {
        min(1, max(0, (speed(at: time) - minimumSpeed) / (maximumSpeed - minimumSpeed)))
    }
}
