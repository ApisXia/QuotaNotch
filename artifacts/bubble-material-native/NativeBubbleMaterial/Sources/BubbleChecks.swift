import Foundation

enum BubbleChecks {
    static func run() throws {
        guard BubbleDemoContent.allCases.count == 6,
              BubbleItemLayout.sampleCounts == [0, 1, 2, 3, 6] else {
            throw BubbleLabError.capture("the sample catalog and 0/1/2/3/6 states must stay available")
        }
        for count in BubbleItemLayout.sampleCounts {
            let placements = BubbleItemLayout.placements(for: count)
            let expectedVisible = min(count, BubbleItemLayout.maximumVisiblePreviews)
            guard placements.count == expectedVisible,
                  placements.map(\.slot) == Array(0..<expectedVisible),
                  BubbleItemLayout.showsOverflowHint(for: count) == (count > 3),
                  placements.allSatisfy({ $0.width > 0 && $0.height > 0 && (0...1).contains($0.opacity) }) else {
                throw BubbleLabError.capture("the \(count)-item layout must keep \(expectedVisible) stable preview slots")
            }
            for diameter in [CGFloat(64), CGFloat(226)] {
                guard placements.allSatisfy({ BubbleItemLayout.maximumVisualRadius(for: $0, diameter: diameter) < diameter * 0.5 }) else {
                    throw BubbleLabError.capture("the \(count)-item layout exceeds the \(Int(diameter))-point shell boundary")
                }
            }
        }
        let sixPlacements = BubbleItemLayout.placements(for: 6)
        let sixContentPairs = sixPlacements.map { BubbleItemLayout.contentPair(for: $0, totalCount: 6) }
        guard BubbleItemLayout.placements(for: 3) == sixPlacements,
              BubbleItemLayout.visiblePreviewCount(for: 4) == 3,
              BubbleItemLayout.showsOverflowHint(for: 4),
              BubbleItemLayout.placements(for: 4) == sixPlacements,
              sixContentPairs.allSatisfy({ $0.front != $0.back }),
              abs(BubbleItemLayout.crossfade(at: 0)) < 0.0001,
              abs(BubbleItemLayout.crossfade(at: BubbleItemLayout.contentCycleDuration / 2) - 1) < 0.0001,
              abs(BubbleItemLayout.crossfade(at: BubbleItemLayout.contentCycleDuration) - 0) < 0.0001 else {
            throw BubbleLabError.capture("the six-item state must reuse stable three-card slots with a smooth content crossfade")
        }

        guard BubbleMotion.arrival(at: -0.01) == .resting else {
            throw BubbleLabError.capture("arrival must be at rest before its trigger")
        }

        let gatherEnd = BubbleMotion.arrival(at: BubbleMotion.gatherDuration)
        guard abs(gatherEnd.shellScale - 1.055) < 0.0001,
              abs(gatherEnd.contentGather - 0.70) < 0.0001 else {
            throw BubbleLabError.capture("gather endpoint changed unexpectedly")
        }

        let holdEnd = BubbleMotion.arrival(at: BubbleMotion.gatherDuration + BubbleMotion.holdDuration)
        guard abs(holdEnd.shellScale - 1.055) < 0.0001,
              holdEnd.contentOpacity == 1 else {
            throw BubbleLabError.capture("the 0.9-second hold must preserve the gathered previews")
        }

        let collapseEnd = BubbleMotion.arrival(at: BubbleMotion.totalDuration)
        guard abs(collapseEnd.shellScale - 0.1055) < 0.0002,
              collapseEnd.shellOpacity == 0,
              collapseEnd.contentOpacity == 0,
              collapseEnd.contentGather == 1 else {
            throw BubbleLabError.capture("the final arrival frame must contract at its own center")
        }

        for step in 0...1_000 {
            let elapsed = BubbleMotion.totalDuration * Double(step) / 1_000
            let frame = BubbleMotion.arrival(at: elapsed)
            let values = [frame.shellScale, frame.shellOpacity, frame.contentGather, frame.contentOpacity]
            guard values.allSatisfy({ $0.isFinite }),
                  (0.10...1.062).contains(frame.shellScale),
                  (0...1).contains(frame.shellOpacity),
                  (0...1).contains(frame.contentGather),
                  (0...1).contains(frame.contentOpacity) else {
                throw BubbleLabError.capture("arrival motion escaped its finite visual bounds at \(elapsed)s")
            }
        }

        let emptyBreath = BubbleMotion.breathing(at: 1.4, populated: false)
        let fullBreath = BubbleMotion.breathing(at: 1.4, populated: true)
        guard fullBreath > emptyBreath else {
            throw BubbleLabError.capture("the populated resting cycle should breathe a little more strongly")
        }
    }
}
