import Foundation

enum BubbleChecks {
    static func run() throws {
        guard BubbleDemoContent.allCases.count == 6,
              BubbleItemLayout.sampleCounts == [0, 1, 2, 3, 6],
              Set(BubbleItemLayout.insertionHistory).count == 6 else {
            throw BubbleLabError.capture("the sample catalog and 0/1/2/3/6 states must stay available")
        }
        for count in BubbleItemLayout.sampleCounts {
            let placements = BubbleItemLayout.placements(for: count)
            let expectedRendered = min(count, BubbleItemLayout.maximumRenderedPreviews)
            guard placements.count == expectedRendered,
                  placements.map(\.slot) == Array(0..<expectedRendered),
                  BubbleItemLayout.showsOverflowHint(for: count) == (count > 3),
                  Set(placements.map(\.content)).count == placements.count,
                  placements.prefix(BubbleItemLayout.maximumVisiblePreviews).allSatisfy({ $0.blur == 0 }),
                  placements.allSatisfy({ $0.width > 0 && $0.height > 0 && (0...1).contains($0.opacity) }) else {
                throw BubbleLabError.capture("the \(count)-item layout must keep stable latest-first preview identities")
            }
            if count > BubbleItemLayout.maximumVisiblePreviews {
                guard placements.count == 4, placements[3].blur > 0,
                      placements[3].content == BubbleItemLayout.insertionHistory[count - 4] else {
                    throw BubbleLabError.capture("the \(count)-item state must show a full blurred fourth preview")
                }
            }
            for diameter in [CGFloat(64), CGFloat(226)] {
                guard placements.allSatisfy({ BubbleItemLayout.maximumVisualRadius(for: $0, diameter: diameter) < diameter * 0.5 }) else {
                    throw BubbleLabError.capture("the \(count)-item layout exceeds the \(Int(diameter))-point shell boundary")
                }
            }
        }
        let settledThree = BubbleInsertionTimeline.frame(at: 0)
        let settledFour = BubbleInsertionTimeline.frame(at: BubbleInsertionTimeline.settledFourTime)
        let settledFive = BubbleInsertionTimeline.frame(at: BubbleInsertionTimeline.settledFiveTime)
        let contentsThree = settledThree.placements.map(\.content)
        let contentsFour = settledFour.placements.map(\.content)
        let contentsFive = settledFive.placements.map(\.content)
        let sharpBottomFour = settledFour.placements.prefix(3)
            .map { BubbleItemLayout.bottomEdgeUnit(for: $0) }
            .max() ?? 0
        let fourthCard = settledFour.placements[3]
        guard contentsThree == [.stillLife, .document, .diagram],
              contentsFour == [.report, .stillLife, .document, .diagram],
              contentsFive == [.fieldNotes, .report, .stillLife, .document],
              settledFour.placements.prefix(3).allSatisfy({ $0.blur == 0 }),
              settledFour.placements.filter({ $0.blur > 0 }).count == 1,
              fourthCard.blur > 0,
              fourthCard.depth < (settledFour.placements.prefix(3).map(\.depth).min() ?? 0),
              BubbleItemLayout.bottomEdgeUnit(for: fourthCard) > sharpBottomFour + 0.06,
              settledFive.placements.prefix(3).allSatisfy({ $0.blur == 0 }),
              settledFive.placements.filter({ $0.blur > 0 }).count == 1,
              settledFive.placements[3].blur > 0,
              reflows([.stillLife, .document, .diagram], from: settledThree.placements, to: settledFour.placements),
              reflows([.report, .stillLife, .document], from: settledFour.placements, to: settledFive.placements) else {
            throw BubbleLabError.capture("new files must lead; the prior third file becomes the blurred fourth")
        }

        let enteringFour = BubbleInsertionTimeline.frame(
            at: BubbleInsertionTimeline.firstInsertStart + BubbleInsertionTimeline.transitionDuration * 0.5
        )
        let enteringFive = BubbleInsertionTimeline.frame(
            at: BubbleInsertionTimeline.secondInsertStart + BubbleInsertionTimeline.transitionDuration * 0.5
        )
        let enteringFourByID = Dictionary(uniqueKeysWithValues: enteringFour.placements.map { ($0.content, $0) })
        let enteringFiveByID = Dictionary(uniqueKeysWithValues: enteringFive.placements.map { ($0.content, $0) })
        guard enteringFour.count == 4,
              Set(enteringFourByID.keys).count == 4,
              let incomingFour = enteringFourByID[.report],
              let oldThird = enteringFourByID[.diagram],
              incomingFour.opacity > 0 && incomingFour.opacity < 0.97,
              oldThird.blur > 0 && oldThird.blur < settledFour.placements[3].blur,
              enteringFourByID[.stillLife]?.x != settledThree.placements[0].x,
              enteringFive.count == 5,
              Set(enteringFiveByID.keys).count == 5,
              let incomingFive = enteringFiveByID[.fieldNotes],
              let movedFourth = enteringFiveByID[.document],
              let outgoingFourth = enteringFiveByID[.diagram],
              incomingFive.opacity > 0 && incomingFive.opacity < 0.97,
              movedFourth.blur > 0 && movedFourth.blur < settledFive.placements[3].blur,
              outgoingFourth.opacity > 0 && outgoingFourth.opacity < 0.88 else {
            throw BubbleLabError.capture("insert transitions must preserve identity while smoothly reflowing and blurring old previews")
        }

        for sample in 0...480 {
            let time = BubbleInsertionTimeline.duration * Double(sample) / 480
            let placements = BubbleInsertionTimeline.frame(at: time).placements
            guard Set(placements.map(\.content)).count == placements.count,
                  placements.allSatisfy({
                      $0.width > 0 && $0.height > 0 && $0.x.isFinite && $0.y.isFinite
                          && $0.rotation.isFinite && $0.opacity.isFinite && (0...1).contains($0.opacity)
                          && $0.blur.isFinite && $0.blur >= 0
                  }) else {
                throw BubbleLabError.capture("an insertion frame has duplicated or invalid preview identities at \(time)s")
            }
            for diameter in [CGFloat(64), CGFloat(226)] {
                guard placements.allSatisfy({ BubbleItemLayout.maximumVisualRadius(for: $0, diameter: diameter) < diameter * 0.5 }) else {
                    throw BubbleLabError.capture("an insertion frame exceeds the \(Int(diameter))-point shell at \(time)s")
                }
            }
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

    private static func reflows(
        _ identities: [BubbleDemoContent],
        from old: [BubblePreviewPlacement],
        to new: [BubblePreviewPlacement]
    ) -> Bool {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.content, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.content, $0) })
        return identities.allSatisfy { identity in
            guard let before = oldByID[identity], let after = newByID[identity] else { return false }
            return hypot(before.x - after.x, before.y - after.y) > 0.04
        }
    }
}
