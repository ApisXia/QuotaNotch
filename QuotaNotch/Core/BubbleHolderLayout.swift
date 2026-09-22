// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The state of the compact holder and the horizontally expanded shelf.  The
/// values in this file are deliberately content-free so the same geometry can
/// be used by the live panel and by the native preview runner.
enum BubbleHolderExpansionDirection: Equatable {
    case above
    case below
}

struct BubbleHolderPage: Equatable {
    let index: Int
    let pageCount: Int
    let start: Int
    let clearCount: Int
    let peekIndex: Int?
    let itemCount: Int

    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index + 1 < pageCount }
}

struct BubbleHolderCardPlacement: Equatable, Identifiable {
    let slot: Int
    let frame: CGRect
    let visibleWidth: CGFloat
    let rotation: Double
    let blur: CGFloat
    let opacity: Double
    let depth: Double
    let isPeek: Bool

    var id: Int { slot }
}

struct BubbleHolderPanelGeometry: Equatable {
    let panelFrame: CGRect
    let canvasSize: CGSize
    let ballCenter: CGPoint
    let rowFrame: CGRect?
    let direction: BubbleHolderExpansionDirection?
    let expanded: Bool

    var ballFrame: CGRect {
        CGRect(x: ballCenter.x - BubbleHolderLayout.ballDiameter / 2,
               y: ballCenter.y - BubbleHolderLayout.ballDiameter / 2,
               width: BubbleHolderLayout.ballDiameter,
               height: BubbleHolderLayout.ballDiameter)
    }

    var interactiveFrames: [CGRect] {
        [ballFrame] + (rowFrame.map { [$0] } ?? [])
    }
}

enum BubbleHolderLayout {
    static let ballDiameter: CGFloat = 75
    static let panelMargin: CGFloat = 3.5
    static let collapsedSize = CGSize(width: 82, height: 82)
    static let rowGap: CGFloat = 12
    static let rowHeight: CGFloat = 84
    static let cardSize = CGSize(width: 66, height: 84)
    static let cardGap: CGFloat = 6
    static let controlWidth: CGFloat = 18
    static let rowPadding: CGFloat = 4
    static let controlGap: CGFloat = 5
    static let peekWidth: CGFloat = 24

    static func page(for itemCount: Int, index: Int) -> BubbleHolderPage {
        let count = max(0, itemCount)
        let pageCount = max(1, (count + 2) / 3)
        let clamped = min(max(0, index), pageCount - 1)
        let start = min(clamped * 3, count)
        let clearCount = min(3, max(0, count - start))
        let peek = start + clearCount < count ? start + clearCount : nil
        return BubbleHolderPage(index: clamped, pageCount: pageCount, start: start,
                                clearCount: clearCount, peekIndex: peek, itemCount: count)
    }

    static func pageIndex(for itemCount: Int, index: Int) -> Int {
        page(for: itemCount, index: index).index
    }

    static func rowWidth(for page: BubbleHolderPage) -> CGFloat {
        // An empty holder has no cards or paging controls, but its compact
        // empty-state label still needs a real hit/render width. Keep this
        // independent of the three-card layout so empty never reserves fake
        // card slots while remaining readable.
        guard page.clearCount > 0 else { return 144 }
        let clearWidth = CGFloat(page.clearCount) * cardSize.width
            + CGFloat(max(0, page.clearCount - 1)) * cardGap
        let peekWidth = page.peekIndex == nil ? 0 : cardGap + Self.peekWidth
        let controls = controlWidth * 2 + controlGap * 2
        return rowPadding * 2 + controls + controlGap + clearWidth + peekWidth
    }

    static func canvasSize(for page: BubbleHolderPage) -> CGSize {
        CGSize(width: max(collapsedSize.width, rowWidth(for: page)),
               height: collapsedSize.height + rowGap + rowHeight)
    }

    /// Computes a frame for a panel whose anchor is the holder's global center.
    /// The frame is clamped to the visible display while `ballCenter` is derived
    /// back from the final frame, so a display-edge adjustment never makes the
    /// SwiftUI ball jump relative to the native panel.
    static func panelGeometry(center: CGPoint, itemCount: Int, expanded: Bool,
                              visibleFrames: [CGRect]) -> BubbleHolderPanelGeometry {
        let page = page(for: itemCount, index: 0)
        let size = expanded ? canvasSize(for: page) : collapsedSize
        let screen = visibleFrames.first(where: { $0.contains(center) }) ?? visibleFrames.min {
            squaredDistance(from: center, to: $0) < squaredDistance(from: center, to: $1)
        } ?? CGRect(origin: .zero, size: size)

        guard expanded else {
            let unclamped = CGRect(x: center.x - size.width / 2,
                                   y: center.y - size.height / 2,
                                   width: size.width, height: size.height)
            let frame = clamp(unclamped, to: screen)
            let localCenter = CGPoint(x: center.x - frame.minX,
                                      y: frame.maxY - center.y)
            return BubbleHolderPanelGeometry(panelFrame: frame, canvasSize: size,
                                             ballCenter: localCenter, rowFrame: nil,
                                             direction: nil, expanded: false)
        }

        let aboveHeight = rowHeight + rowGap + ballDiameter / 2
        let belowHeight = rowHeight + rowGap + ballDiameter / 2
        let canPlaceAbove = center.y + aboveHeight <= screen.maxY
        let canPlaceBelow = center.y - belowHeight >= screen.minY
        let direction: BubbleHolderExpansionDirection = canPlaceAbove || !canPlaceBelow ? .above : .below

        let originY: CGFloat
        switch direction {
        case .above:
            originY = center.y - ballDiameter / 2
        case .below:
            originY = center.y - ballDiameter / 2 - rowGap - rowHeight
        }
        let unclamped = CGRect(x: center.x - size.width / 2, y: originY,
                               width: size.width, height: size.height)
        let frame = clamp(unclamped, to: screen)
        let localCenter = CGPoint(x: center.x - frame.minX,
                                  y: frame.maxY - center.y)
        let rowWidth = Self.rowWidth(for: page)
        let rowX = (size.width - rowWidth) / 2
        let rowY: CGFloat
        switch direction {
        case .above:
            rowY = localCenter.y - ballDiameter / 2 - rowGap - rowHeight
        case .below:
            rowY = localCenter.y + ballDiameter / 2 + rowGap
        }
        let rowFrame = CGRect(x: rowX, y: rowY, width: rowWidth, height: rowHeight)
        return BubbleHolderPanelGeometry(panelFrame: frame, canvasSize: size,
                                         ballCenter: localCenter, rowFrame: rowFrame,
                                         direction: direction, expanded: true)
    }

    /// Source stack coordinates copied from the approved 75pt collector preview.
    /// Keeping these normalized values here makes progress=0 exactly the same
    /// arrangement as the compact holder instead of introducing a second glyph.
    private static func stackPlacements(for visibleCount: Int) -> [(CGFloat, CGFloat, CGFloat, CGFloat, Double, Double)] {
        switch visibleCount {
        case ...1:
            return [(0.43, 0.54, -0.06, 0.04, -4, 0.98)]
        case 2:
            return [
                (0.34, 0.41, -0.15, -0.05, -9, 0.96),
                (0.34, 0.40, 0.14, 0.05, 7, 0.88)
            ]
        case 3:
            return [
                (0.37, 0.46, -0.14, -0.02, -5, 0.98),
                (0.28, 0.37, 0.16, -0.09, 6, 0.91),
                (0.27, 0.34, 0.09, 0.18, 8, 0.94)
            ]
        default:
            return [
                (0.32, 0.40, -0.120, -0.045, -8, 0.97),
                (0.30, 0.37, 0.130, -0.115, 4, 0.97),
                (0.28, 0.35, 0.055, 0.075, 9, 0.97),
                (0.26, 0.32, -0.015, 0.142, 2, 0.88)
            ]
        }
    }

    static func collapsedPlacements(page: BubbleHolderPage, ballCenter: CGPoint) -> [BubbleHolderCardPlacement] {
        let visibleCount = page.peekIndex == nil ? page.clearCount : 4
        guard visibleCount > 0 else { return [] }
        let source = stackPlacements(for: visibleCount)
        return source.enumerated().map { index, item in
            let width = item.0 * ballDiameter
            let height = item.1 * ballDiameter
            let frame = CGRect(x: ballCenter.x + item.2 * ballDiameter - width / 2,
                               y: ballCenter.y + item.3 * ballDiameter - height / 2,
                               width: width, height: height)
            let isPeek = index == 3 && page.peekIndex != nil
            return BubbleHolderCardPlacement(slot: index, frame: frame,
                                             visibleWidth: frame.width,
                                             rotation: item.4,
                                             blur: isPeek ? ballDiameter * 0.020 : 0,
                                             opacity: isPeek ? 0.88 : item.5,
                                             depth: Double(visibleCount - index),
                                             isPeek: isPeek)
        }
    }

    static func previewGeometry(itemCount: Int, expanded: Bool,
                                direction: BubbleHolderExpansionDirection = .above) -> BubbleHolderPanelGeometry {
        let page = page(for: itemCount, index: 0)
        let size = expanded ? canvasSize(for: page) : collapsedSize
        let center = CGPoint(x: size.width / 2,
                             y: expanded && direction == .above
                                ? size.height - ballDiameter / 2
                                : ballDiameter / 2)
        let row = expanded ? CGRect(x: (size.width - rowWidth(for: page)) / 2,
                                    y: direction == .above
                                        ? center.y - ballDiameter / 2 - rowGap - rowHeight
                                        : center.y + ballDiameter / 2 + rowGap,
                                    width: rowWidth(for: page), height: rowHeight) : nil
        return BubbleHolderPanelGeometry(panelFrame: CGRect(origin: .zero, size: size),
                                         canvasSize: size, ballCenter: center,
                                         rowFrame: row, direction: expanded ? direction : nil,
                                         expanded: expanded)
    }

    static func expandedPlacements(page: BubbleHolderPage, rowFrame: CGRect) -> [BubbleHolderCardPlacement] {
        let clearWidth = CGFloat(page.clearCount) * cardSize.width
            + CGFloat(max(0, page.clearCount - 1)) * cardGap
        let groupWidth = clearWidth + (page.peekIndex == nil ? 0 : cardGap + peekWidth)
        let firstX = rowFrame.midX - groupWidth / 2
        var placements: [BubbleHolderCardPlacement] = []
        for slot in 0..<page.clearCount {
            let x = firstX + CGFloat(slot) * (cardSize.width + cardGap)
            placements.append(BubbleHolderCardPlacement(
                slot: slot,
                frame: CGRect(x: x, y: rowFrame.minY, width: cardSize.width, height: cardSize.height),
                visibleWidth: cardSize.width, rotation: 0, blur: 0, opacity: 1,
                depth: Double(page.clearCount - slot), isPeek: false))
        }
        if page.peekIndex != nil {
            let x = firstX + CGFloat(page.clearCount) * (cardSize.width + cardGap)
            placements.append(BubbleHolderCardPlacement(
                slot: page.clearCount,
                frame: CGRect(x: x, y: rowFrame.minY, width: cardSize.width, height: cardSize.height),
                visibleWidth: peekWidth, rotation: 0, blur: 5.5, opacity: 0.68,
                depth: 0, isPeek: true))
        }
        return placements
    }

    static func interpolate(_ source: BubbleHolderCardPlacement,
                            _ destination: BubbleHolderCardPlacement,
                            progress: CGFloat) -> BubbleHolderCardPlacement {
        let t = min(1, max(0, progress))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let frame = CGRect(x: mix(source.frame.minX, destination.frame.minX),
                           y: mix(source.frame.minY, destination.frame.minY),
                           width: mix(source.frame.width, destination.frame.width),
                           height: mix(source.frame.height, destination.frame.height))
        return BubbleHolderCardPlacement(
            slot: source.slot,
            frame: frame,
            visibleWidth: mix(source.visibleWidth, destination.visibleWidth),
            rotation: source.rotation + (destination.rotation - source.rotation) * Double(t),
            blur: mix(source.blur, destination.blur),
            opacity: source.opacity + (destination.opacity - source.opacity) * Double(t),
            depth: source.depth + (destination.depth - source.depth) * Double(t),
            isPeek: destination.isPeek)
    }

    static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        var result = frame
        if result.width <= visible.width {
            result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        } else {
            result.origin.x = visible.minX
        }
        if result.height <= visible.height {
            result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        } else {
            result.origin.y = visible.minY
        }
        return result
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
