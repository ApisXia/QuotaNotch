import Foundation

struct ArrivalFrame: Equatable {
    let shellScale: CGFloat
    let shellOpacity: CGFloat
    let flakeGather: CGFloat
    let flakeOpacity: CGFloat

    static let resting = ArrivalFrame(
        shellScale: 1,
        shellOpacity: 1,
        flakeGather: 0,
        flakeOpacity: 1
    )
}

enum BubbleMotion {
    static let gatherDuration = 0.45
    static let holdDuration = 0.90
    static let collapseDuration = 0.70
    static let totalDuration = gatherDuration + holdDuration + collapseDuration

    static func arrival(at elapsed: TimeInterval) -> ArrivalFrame {
        guard elapsed >= 0 else { return .resting }

        if elapsed < gatherDuration {
            let progress = smoothstep(elapsed / gatherDuration)
            return ArrivalFrame(
                shellScale: 1 + 0.055 * progress,
                shellOpacity: 1,
                flakeGather: progress * 0.70,
                flakeOpacity: 1
            )
        }

        let holdEnd = gatherDuration + holdDuration
        if elapsed < holdEnd {
            let holdProgress = (elapsed - gatherDuration) / holdDuration
            let breathing = 0.006 * sin(holdProgress * .pi)
            return ArrivalFrame(
                shellScale: 1.055 + breathing,
                shellOpacity: 1,
                flakeGather: 0.70 + 0.08 * sin(holdProgress * 2 * .pi),
                flakeOpacity: 1
            )
        }

        let progress = min(1, max(0, (elapsed - holdEnd) / collapseDuration))
        let eased = smoothstep(progress)
        return ArrivalFrame(
            shellScale: 1.055 * (1 - 0.90 * eased),
            shellOpacity: 1 - smoothstep((progress - 0.55) / 0.45),
            flakeGather: 0.78 + 0.22 * eased,
            flakeOpacity: 1 - smoothstep((progress - 0.14) / 0.76)
        )
    }

    static func breathing(at time: TimeInterval, populated: Bool) -> CGFloat {
        let cycle = 0.5 + 0.5 * sin(time * 0.68)
        return CGFloat(cycle) * (populated ? 1.45 : 1)
    }

    private static func smoothstep(_ value: TimeInterval) -> CGFloat {
        let t = CGFloat(min(1, max(0, value)))
        return t * t * (3 - 2 * t)
    }
}
