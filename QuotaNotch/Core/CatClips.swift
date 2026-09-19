// SPDX-License-Identifier: GPL-3.0-only
// Authored timings from the approved cheek-v6 / transitions-v8 previews.
import Foundation

struct CatFrameStep: Equatable {
    let duration: Double
    let asset: String
    let travel: CGFloat
}
struct CatClip: Equatable {
    let steps: [CatFrameStep]
    let fullBody: Bool
    var duration: Double { steps.reduce(0) { $0 + $1.duration } }
    func step(at elapsed: Double) -> CatFrameStep {
        var remaining = max(0, elapsed)
        for step in steps { if remaining < step.duration { return step }; remaining -= step.duration }
        return steps.last!
    }
}
enum CatClips {
    static let gentle = CatClip(steps: [
        .init(duration: 0.800, asset: "Cat-cheek-rub-0", travel: 0),
        .init(duration: 0.300, asset: "Cat-cheek-rub-0", travel: 8),
        .init(duration: 0.350, asset: "Cat-cheek-rub-1", travel: 16),
        .init(duration: 0.450, asset: "Cat-cheek-rub-2", travel: 24),
        .init(duration: 0.650, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 0.450, asset: "Cat-cheek-rub-4", travel: 24),
        .init(duration: 0.900, asset: "Cat-cheek-rub-5", travel: 24),
        .init(duration: 0.200, asset: "Cat-cheek-rub-0", travel: 13),
        .init(duration: 0.200, asset: "Cat-cheek-rub-0", travel: 5),
        .init(duration: 1.200, asset: "Cat-cheek-rub-0", travel: 0),
    ], fullBody: false)
    static let completed = CatClip(steps: [
        .init(duration: 0.800, asset: "Cat-cheek-rub-0", travel: 0),
        .init(duration: 0.300, asset: "Cat-cheek-rub-0", travel: 8),
        .init(duration: 0.350, asset: "Cat-cheek-rub-1", travel: 16),
        .init(duration: 0.400, asset: "Cat-cheek-rub-2", travel: 24),
        .init(duration: 0.450, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 0.450, asset: "Cat-cheek-rub-4", travel: 24),
        .init(duration: 0.350, asset: "Cat-cheek-rub-2", travel: 24),
        .init(duration: 0.500, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 0.500, asset: "Cat-cheek-rub-4", travel: 24),
        .init(duration: 0.900, asset: "Cat-cheek-rub-5", travel: 24),
        .init(duration: 0.200, asset: "Cat-cheek-rub-0", travel: 13),
        .init(duration: 0.200, asset: "Cat-cheek-rub-0", travel: 5),
        .init(duration: 1.200, asset: "Cat-cheek-rub-0", travel: 0),
    ], fullBody: false)
    static let attention = CatClip(steps: [
        .init(duration: 0.800, asset: "Cat-cheek-rub-0", travel: 0),
        .init(duration: 0.300, asset: "Cat-cheek-rub-0", travel: 8),
        .init(duration: 0.350, asset: "Cat-cheek-rub-1", travel: 16),
        .init(duration: 0.450, asset: "Cat-cheek-rub-2", travel: 24),
        .init(duration: 0.600, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 1.650, asset: "Cat-cheek-rub-4", travel: 24),
        .init(duration: 1.100, asset: "Cat-cheek-rub-5", travel: 24),
        .init(duration: 0.200, asset: "Cat-cheek-rub-0", travel: 13),
        .init(duration: 0.200, asset: "Cat-cheek-rub-0", travel: 5),
        .init(duration: 1.200, asset: "Cat-cheek-rub-0", travel: 0),
    ], fullBody: false)
    static let body = CatClip(steps: [
        .init(duration: 0.900, asset: "Cat-edge-step-0", travel: 0),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 1),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 2),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 3),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 4),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 5),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 6),
        .init(duration: 0.140, asset: "Cat-edge-step-7", travel: 7),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 8),
        .init(duration: 0.300, asset: "Cat-edge-step-0", travel: 8),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 9),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 10),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 11),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 12),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 13),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 14),
        .init(duration: 0.140, asset: "Cat-edge-step-7", travel: 15),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 16),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 17),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 18),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 19),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 20),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 21),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 22),
        .init(duration: 0.140, asset: "Cat-edge-step-7", travel: 23),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 24),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 25),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 26),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 27),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 28),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 29),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 30),
        .init(duration: 0.120, asset: "Cat-edge-step-7", travel: 30),
        .init(duration: 0.500, asset: "Cat-edge-step-0", travel: 30),
        .init(duration: 0.300, asset: "Cat-edge-step-0", travel: 30),
        .init(duration: 0.240, asset: "Cat-body-sequence-1", travel: 30),
        .init(duration: 1.000, asset: "Cat-body-sequence-2", travel: 30),
        .init(duration: 0.280, asset: "Cat-body-sequence-3", travel: 30),
        .init(duration: 0.280, asset: "Cat-body-sequence-4", travel: 30),
        .init(duration: 0.400, asset: "Cat-tail-bridge-1", travel: 30),
        .init(duration: 0.450, asset: "Cat-tail-bridge-2", travel: 30),
        .init(duration: 0.550, asset: "Cat-tail-bridge-3", travel: 30),
        .init(duration: 2.400, asset: "Cat-tail-bridge-3", travel: 30),
        .init(duration: 1.200, asset: "Cat-tail-bridge-2", travel: 30),
        .init(duration: 0.300, asset: "Cat-tail-bridge-2", travel: 30),
        .init(duration: 0.300, asset: "Cat-tail-bridge-1", travel: 30),
        .init(duration: 0.280, asset: "Cat-body-sequence-4", travel: 30),
        .init(duration: 0.280, asset: "Cat-body-sequence-3", travel: 30),
        .init(duration: 0.260, asset: "Cat-edge-step-0", travel: 30),
        .init(duration: 0.220, asset: "Cat-edge-step-0", travel: 30),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 29),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 28),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 27),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 26),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 25),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 24),
        .init(duration: 0.140, asset: "Cat-edge-step-7", travel: 23),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 22),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 21),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 20),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 19),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 18),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 17),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 16),
        .init(duration: 0.140, asset: "Cat-edge-step-7", travel: 15),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 14),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 13),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 12),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 11),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 10),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 9),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 8),
        .init(duration: 0.140, asset: "Cat-edge-step-7", travel: 7),
        .init(duration: 0.080, asset: "Cat-edge-step-6", travel: 6),
        .init(duration: 0.080, asset: "Cat-edge-step-5", travel: 5),
        .init(duration: 0.140, asset: "Cat-edge-step-4", travel: 4),
        .init(duration: 0.080, asset: "Cat-edge-step-3", travel: 3),
        .init(duration: 0.080, asset: "Cat-edge-step-2", travel: 2),
        .init(duration: 0.080, asset: "Cat-edge-step-1", travel: 1),
        .init(duration: 0.140, asset: "Cat-edge-step-0", travel: 0),
        .init(duration: 1.200, asset: "Cat-edge-step-0", travel: 0),
    ], fullBody: true)
    // Distinct poses using the approved pixels: watch with open eyes, doze, or rub.
    static let watch = CatClip(steps: [
        .init(duration: 0.15, asset: "Cat-cheek-rub-0", travel: 0),
        .init(duration: 0.25, asset: "Cat-cheek-rub-0", travel: 8),
        .init(duration: 0.4, asset: "Cat-cheek-rub-1", travel: 16),
        .init(duration: 1.2, asset: "Cat-cheek-rub-0", travel: 24),
        .init(duration: 0.7, asset: "Cat-cheek-rub-5", travel: 24),
        .init(duration: 0.15, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 0.8, asset: "Cat-cheek-rub-0", travel: 24),
        .init(duration: 0.2, asset: "Cat-cheek-rub-0", travel: 12),
        .init(duration: 0.2, asset: "Cat-cheek-rub-0", travel: 0),
    ], fullBody: false)
    static let doze = CatClip(steps: [
        .init(duration: 0.15, asset: "Cat-cheek-rub-0", travel: 0),
        .init(duration: 0.25, asset: "Cat-cheek-rub-0", travel: 8),
        .init(duration: 0.3, asset: "Cat-cheek-rub-1", travel: 16),
        .init(duration: 0.6, asset: "Cat-cheek-rub-0", travel: 24),
        .init(duration: 1.6, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 0.3, asset: "Cat-cheek-rub-5", travel: 24),
        .init(duration: 1.1, asset: "Cat-cheek-rub-3", travel: 24),
        .init(duration: 0.45, asset: "Cat-cheek-rub-0", travel: 24),
        .init(duration: 0.2, asset: "Cat-cheek-rub-0", travel: 12),
        .init(duration: 0.2, asset: "Cat-cheek-rub-0", travel: 0),
    ], fullBody: false)
    // Only the edge of the head fits: try twice, pause, then withdraw.
    // This occupies existing wing pixels; it never increases the shell width.
    static let crowded = CatClip(steps: [
        .init(duration: 0.1, asset: "Cat-cheek-rub-0", travel: 0),
        .init(duration: 0.3, asset: "Cat-cheek-rub-0", travel: 4),
        .init(duration: 0.3, asset: "Cat-cheek-rub-1", travel: 7),
        .init(duration: 0.35, asset: "Cat-cheek-rub-2", travel: 8),
        .init(duration: 0.25, asset: "Cat-cheek-rub-0", travel: 5),
        .init(duration: 0.35, asset: "Cat-cheek-rub-2", travel: 8),
        .init(duration: 0.45, asset: "Cat-cheek-rub-5", travel: 6),
        .init(duration: 0.25, asset: "Cat-cheek-rub-0", travel: 3),
        .init(duration: 0.25, asset: "Cat-cheek-rub-0", travel: 0),
    ], fullBody: false)
    static let interactions = [gentle, watch, doze]
    static let idleVariants = [watch, doze, gentle]
    static func head(_ action: CatAction) -> CatClip {
        switch action { case .completed: return completed; case .attention, .rest: return attention; default: return gentle }
    }
}
