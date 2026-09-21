// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Small deterministic rules shared by the global-event collector and its tests.
enum BubbleCollectorPolicy {
    static func shouldPersistPausedStartup(hasBeenConfigured: Bool) -> Bool {
        hasBeenConfigured
    }

    static func shouldPresentSelection(
        receiving: Bool,
        sourceProcessID: Int32?,
        ownProcessID: Int32,
        isSecureField: Bool,
        oldFingerprint: String?,
        newFingerprint: String?
    ) -> Bool {
        guard receiving, !isSecureField,
              let sourceProcessID, sourceProcessID != ownProcessID,
              let newFingerprint, !newFingerprint.isEmpty else { return false }
        return oldFingerprint != newFingerprint
    }

    static func shouldPreviewDrag(
        receiving: Bool,
        sourceProcessID: Int32?,
        ownProcessID: Int32,
        pasteboardChanged: Bool,
        types: Set<String>
    ) -> Bool {
        guard receiving, pasteboardChanged,
              let sourceProcessID, sourceProcessID != ownProcessID else { return false }
        return !types.isDisjoint(with: supportedDragTypes)
    }

    static let supportedDragTypes: Set<String> = [
        "public.file-url", "public.url", "public.utf8-plain-text", "public.plain-text",
        "public.png", "public.jpeg", "public.tiff"
    ]
}

enum BubbleCollectorGeometry {
    /// Places a stationary panel beside its trigger and keeps its whole frame on one display.
    static func panelFrame(
        anchor: CGPoint,
        size: CGSize,
        visibleFrames: [CGRect],
        cursorClearance: CGFloat = 24,
        gap: CGFloat = 18
    ) -> CGRect {
        let fallback = CGRect(origin: .zero, size: size)
        guard !visibleFrames.isEmpty else { return fallback }
        let screen = visibleFrames.first(where: { $0.contains(anchor) }) ?? visibleFrames.min {
            squaredDistance(from: anchor, to: $0) < squaredDistance(from: anchor, to: $1)
        }!

        // Start below-right of the selected text/cursor. If that would leave too
        // little room, flip above/left before clamping to the display work area.
        var x = anchor.x + cursorClearance
        var y = anchor.y - size.height - gap
        if x + size.width > screen.maxX { x = anchor.x - size.width - cursorClearance }
        if y < screen.minY { y = anchor.y + gap }
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - size.width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
