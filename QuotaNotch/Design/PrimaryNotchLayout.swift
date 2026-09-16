// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The first child owns the width. Every other child is measured at that width
/// and stacked below it. Accessories never participate in primary sizing.
/// This layout has no knowledge of music, quotas, event types or icon counts.
struct PrimaryNotchLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let primary = subviews.first else { return .zero }
        let size = primary.sizeThatFits(.unspecified)
        let accessoryProposal = ProposedViewSize(width: size.width, height: nil)
        let extraHeight = subviews.dropFirst().reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(accessoryProposal).height
        }
        return CGSize(width: size.width, height: size.height + extraHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let primary = subviews.first else { return }
        let size = primary.sizeThatFits(.unspecified)
        primary.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
        var y = bounds.minY + size.height
        for accessory in subviews.dropFirst() {
            let proposal = ProposedViewSize(width: size.width, height: nil)
            let height = accessory.sizeThatFits(proposal).height
            accessory.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                            proposal: ProposedViewSize(width: size.width, height: height))
            y += height
        }
    }
}
