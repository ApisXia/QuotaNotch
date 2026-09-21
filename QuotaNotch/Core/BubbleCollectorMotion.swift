// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct BubbleCollectorMotionFrame: Equatable {
    let shellScale: CGFloat
    let shellOpacity: CGFloat
    let contentOpacity: CGFloat

    static let resting = BubbleCollectorMotionFrame(shellScale: 1, shellOpacity: 1, contentOpacity: 1)
}

enum BubbleCollectorMotion {
    static let gatherDuration: TimeInterval = 0.45
    static let holdDuration: TimeInterval = 0.90
    static let collapseDuration: TimeInterval = 0.70
    static let totalDuration = gatherDuration + holdDuration + collapseDuration

    static func frame(at elapsed: TimeInterval) -> BubbleCollectorMotionFrame {
        guard elapsed >= 0 else { return .resting }
        if elapsed < gatherDuration {
            let progress = smooth(elapsed / gatherDuration)
            return BubbleCollectorMotionFrame(shellScale: 1 + 0.055 * progress,
                                              shellOpacity: 1,
                                              contentOpacity: 1)
        }
        let holdEnd = gatherDuration + holdDuration
        if elapsed < holdEnd {
            let holdProgress = (elapsed - gatherDuration) / holdDuration
            let breathing = 0.006 * sin(holdProgress * .pi)
            return BubbleCollectorMotionFrame(shellScale: 1.055 + breathing,
                                              shellOpacity: 1,
                                              contentOpacity: 1)
        }
        let progress = smooth((elapsed - holdEnd) / collapseDuration)
        return BubbleCollectorMotionFrame(shellScale: 1.055 * (1 - 0.90 * progress),
                                          shellOpacity: 1 - smooth((progress - 0.55) / 0.45),
                                          contentOpacity: 1 - smooth((progress - 0.14) / 0.76))
    }

    private static func smooth(_ value: TimeInterval) -> CGFloat {
        let t = CGFloat(min(1, max(0, value)))
        return t * t * (3 - 2 * t)
    }
}
