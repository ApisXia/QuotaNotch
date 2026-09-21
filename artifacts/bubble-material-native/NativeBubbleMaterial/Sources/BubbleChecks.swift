import Foundation

enum BubbleChecks {
    static func run() throws {
        guard BubbleMotion.arrival(at: -0.01) == .resting else {
            throw BubbleLabError.capture("arrival must be at rest before its trigger")
        }

        let gatherEnd = BubbleMotion.arrival(at: BubbleMotion.gatherDuration)
        guard abs(gatherEnd.shellScale - 1.055) < 0.0001,
              abs(gatherEnd.flakeGather - 0.70) < 0.0001 else {
            throw BubbleLabError.capture("gather endpoint changed unexpectedly")
        }

        let holdEnd = BubbleMotion.arrival(at: BubbleMotion.gatherDuration + BubbleMotion.holdDuration)
        guard abs(holdEnd.shellScale - 1.055) < 0.0001,
              holdEnd.flakeOpacity == 1 else {
            throw BubbleLabError.capture("the 0.9-second hold must preserve the gathered flakes")
        }

        let collapseEnd = BubbleMotion.arrival(at: BubbleMotion.totalDuration)
        guard abs(collapseEnd.shellScale - 0.1055) < 0.0002,
              collapseEnd.shellOpacity == 0,
              collapseEnd.flakeOpacity == 0,
              collapseEnd.flakeGather == 1 else {
            throw BubbleLabError.capture("the final arrival frame must contract at its own center")
        }

        for step in 0...1_000 {
            let elapsed = BubbleMotion.totalDuration * Double(step) / 1_000
            let frame = BubbleMotion.arrival(at: elapsed)
            let values = [frame.shellScale, frame.shellOpacity, frame.flakeGather, frame.flakeOpacity]
            guard values.allSatisfy({ $0.isFinite }),
                  (0.10...1.06).contains(frame.shellScale),
                  (0...1).contains(frame.shellOpacity),
                  (0...1).contains(frame.flakeGather),
                  (0...1).contains(frame.flakeOpacity) else {
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
