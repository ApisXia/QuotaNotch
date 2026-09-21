import Foundation

enum BubbleChecks {
    static func run() throws {
        guard BubbleDemoContent.allCases.count == 6,
              BubbleItemLayout.sampleCounts == [0, 1, 2, 3, 6],
              BubbleItemLayout.insertionHistory.count == 6,
              Set(BubbleItemLayout.insertionHistory).count == 6,
              BubbleInsertionTimeline.insertionStartTimes.count == 5,
              BubbleInsertionTimeline.insertionStartTimes.first! > 0,
              BubbleInsertionTimeline.insertionStartTimes.last! + BubbleInsertionTimeline.transitionDuration < BubbleInsertionTimeline.duration,
              zip(BubbleInsertionTimeline.insertionStartTimes, BubbleInsertionTimeline.insertionStartTimes.dropFirst())
                  .allSatisfy({ pair in pair.1 - pair.0 > BubbleInsertionTimeline.transitionDuration }),
              BubbleInsertionTimeline.duration >= 18,
              BubbleInsertionTimeline.duration <= 22 else {
            throw BubbleLabError.capture("the sample catalog and complete 0→5 insertion timeline must stay available")
        }
        for count in 0...6 {
            let placements = BubbleItemLayout.placements(for: count)
            let expectedRendered = min(count, BubbleItemLayout.maximumRenderedPreviews)
            let expectedContents = Array(BubbleItemLayout.insertionHistory.prefix(count).reversed().prefix(expectedRendered))
            guard placements.count == expectedRendered,
                  placements.map(\.slot) == Array(0..<expectedRendered),
                  placements.map(\.content) == expectedContents,
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

        let settledFrames = Dictionary(uniqueKeysWithValues: (0...5).map { count in
            (count, BubbleInsertionTimeline.frame(at: BubbleInsertionTimeline.settledTime(for: count)))
        })
        guard (0...5).allSatisfy({ count in
            guard let frame = settledFrames[count] else { return false }
            let expected = Array(BubbleItemLayout.insertionHistory.prefix(count).reversed().prefix(4))
            return frame.count == count && frame.placements.map(\.content) == expected
        }),
        let settledTwo = settledFrames[2],
        let settledThree = settledFrames[3],
        let settledFour = settledFrames[4],
        let settledFive = settledFrames[5] else {
            throw BubbleLabError.capture("settled 0→5 steps must use one chronological latest-first content identity order")
        }
        let contentsThree = settledThree.placements.map(\.content)
        let contentsFour = settledFour.placements.map(\.content)
        let contentsFive = settledFive.placements.map(\.content)
        let sharpBottomFour = settledFour.placements.prefix(3)
            .map { BubbleItemLayout.bottomEdgeUnit(for: $0) }
            .max() ?? 0
        let sharpAreaFour = settledFour.placements.prefix(3)
            .reduce(0.0) { $0 + Double($1.width * $1.height) * $1.opacity }
        let sharpCenterYFour = settledFour.placements.prefix(3)
            .reduce(0.0) { $0 + Double($1.y) * Double($1.width * $1.height) * $1.opacity }
            / sharpAreaFour
        let fourthCard = settledFour.placements[3]
        let fourthPeek = BubbleItemLayout.bottomEdgeUnit(for: fourthCard) - sharpBottomFour
        guard settledFrames[0]?.placements.isEmpty == true,
              settledFrames[1]?.placements.map(\.content) == [.stillLife],
              settledTwo.placements.map(\.content) == [.document, .stillLife],
              contentsThree == [.diagram, .document, .stillLife],
              contentsFour == [.report, .diagram, .document, .stillLife],
              contentsFive == [.fieldNotes, .report, .diagram, .document],
              settledTwo.placements[0].depth > settledTwo.placements[1].depth,
              settledFour.placements.prefix(3).allSatisfy({ $0.blur == 0 }),
              settledFour.placements.filter({ $0.blur > 0 }).count == 1,
              fourthCard.blur > 0,
              fourthCard.depth < (settledFour.placements.prefix(3).map(\.depth).min() ?? 0),
              (0.045...0.070).contains(fourthPeek),
              (-0.060 ... -0.010).contains(sharpCenterYFour),
              abs(settledFour.placements[0].y - settledFour.placements[1].y) > 0.050,
              settledFive.placements[3].content == .document,
              settledFive.placements.prefix(3).allSatisfy({ $0.blur == 0 }),
              settledFive.placements.filter({ $0.blur > 0 }).count == 1,
              settledFive.placements[3].blur > 0 else {
            throw BubbleLabError.capture("new files must lead and the prior third file must become the compact blurred fourth")
        }

        for newCount in 1...5 {
            let start = BubbleInsertionTimeline.insertionStartTimes[newCount - 1]
            let oldFrame = settledFrames[newCount - 1]!
            let newFrame = settledFrames[newCount]!
            let before = BubbleInsertionTimeline.frame(at: start - 0.01)
            let beginning = BubbleInsertionTimeline.frame(at: start)
            let middle = BubbleInsertionTimeline.frame(at: start + BubbleInsertionTimeline.transitionDuration * 0.5)
            let ending = BubbleInsertionTimeline.frame(at: start + BubbleInsertionTimeline.transitionDuration)
            let middleIDs = Set(middle.placements.map(\.content))
            let expectedTransitionIDs = Set(oldFrame.placements.map(\.content))
                .union(Set(newFrame.placements.map(\.content)))
            let newest = BubbleItemLayout.insertionHistory[newCount - 1]
            let middleByID = Dictionary(uniqueKeysWithValues: middle.placements.map { ($0.content, $0) })
            let sharedOlderIDs = Array(Set(oldFrame.placements.map(\.content))
                .intersection(Set(newFrame.placements.map(\.content))))
            let moveCheck = oldFrame.placements.isEmpty || reflows(sharedOlderIDs, from: oldFrame.placements, to: newFrame.placements)
            guard let incoming = middleByID[newest], let settledIncoming = newFrame.placements.first else {
                throw BubbleLabError.capture("the \(newCount - 1)→\(newCount) insertion lost its newest preview identity")
            }
            let olderDepth = middle.placements.filter({ $0.content != newest }).map(\.depth).max() ?? -Double.infinity
            let outgoingThird = newCount == 4 ? middleByID[.stillLife] : nil
            let outgoingFourth = newCount == 5 ? middleByID[.stillLife] : nil
            guard before.count == newCount - 1,
                  beginning.count == newCount,
                  ending.count == newCount,
                  middle.count == expectedTransitionIDs.count,
                  middleIDs == expectedTransitionIDs,
                  middle.placements.first?.content == newest,
                  incoming.opacity > 0,
                  incoming.opacity < settledIncoming.opacity,
                  incoming.depth > olderDepth,
                  newCount != 4 || (outgoingThird?.blur ?? 0) > 0,
                  newCount != 5 || ((outgoingFourth?.opacity ?? 0) > 0 && (outgoingFourth?.opacity ?? 1) < 0.88),
                  moveCheck else {
                throw BubbleLabError.capture("the \(newCount - 1)→\(newCount) insert must add one newest identity and smoothly reflow older previews")
            }
        }

        for sample in 0...800 {
            let time = BubbleInsertionTimeline.duration * Double(sample) / 800
            let frame = BubbleInsertionTimeline.frame(at: time)
            let placements = frame.placements
            guard Set(placements.map(\.content)).count == placements.count,
                  (0...5).contains(frame.count),
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

        guard NotchDemoPresentation.allCases == [.widget, .dualWing, .minimal],
              NotchDemoPresentation.widget.iconSize == 20,
              NotchDemoPresentation.dualWing.iconSize == 20,
              NotchDemoPresentation.minimal.iconSize == 14,
              NotchDemoState.receivingEmpty.itemCount == 0,
              NotchDemoState.pausedEmpty.itemCount == 0,
              NotchDemoState.receivingPopulated.itemCount == 3,
              NotchDemoState.pausedPopulated.itemCount == 3,
              NotchDemoState.receivingEmpty.shortStatus == NotchDemoState.receivingPopulated.shortStatus,
              NotchDemoState.pausedEmpty.shortStatus == NotchDemoState.pausedPopulated.shortStatus,
              NotchDemoState.allCases.count == 4,
              NotchContentCountBoard.counts == [0, 1, 2, 3, 6],
              abs(NotchSignalMotion.angle(at: 0) - NotchSignalMotion.angle(at: 8)) < 0.0001,
              NotchSignalMotion.angle(at: 2) > NotchSignalMotion.angle(at: 0),
              NotchSignalMotion.angle(at: 4) > NotchSignalMotion.angle(at: 2),
              NotchSignalMotion.angle(at: 6) > NotchSignalMotion.angle(at: 4),
              NotchSignalMotion.normalizedProgress(at: 4) > NotchSignalMotion.normalizedProgress(at: 2),
              hypot(NotchSignalMotion.radialFraction, NotchSignalMotion.maximumBarFraction * 0.5) < 0.5 else {
            throw BubbleLabError.capture("the 20pt/14pt notch matrix and localized eight-second receive signal must preserve all four state semantics")
        }
        for size in [CGFloat(14), CGFloat(20)] {
            let unit = size / 28
            let frontDiameter = size * 24 / 28
            let strokeMargin = max(0.42, 0.9 * unit) * 0.5
            let frontCenter = CGPoint(x: size * 0.5 - 1.5 * unit, y: size * 0.5 + 1.5 * unit)
            let radius = frontDiameter * 0.5
            guard frontCenter.x - radius - strokeMargin >= -0.001,
                  frontCenter.y - radius - strokeMargin >= -0.001,
                  frontCenter.x + radius + strokeMargin <= size + 0.001,
                  frontCenter.y + radius + strokeMargin <= size + 0.001 else {
                throw BubbleLabError.capture("the small symbol must keep the complete closed front loop stroke inside its notch slot")
            }
            let rearCenter = CGPoint(x: size * 0.5 + 2 * unit, y: size * 0.5 - 1.5 * unit)
            let rearRadius = size * 12 / 28
            let rearStart = -1.30
            let rearEnd = 0.42
            let rearMinimumX = rearCenter.x + rearRadius * CGFloat(cos(rearStart)) - strokeMargin
            let rearMaximumX = rearCenter.x + rearRadius * CGFloat(cos(rearEnd)) + strokeMargin
            let rearMinimumY = rearCenter.y + rearRadius * CGFloat(sin(rearStart)) - strokeMargin
            let rearMaximumY = rearCenter.y + rearRadius * CGFloat(sin(rearEnd)) + strokeMargin
            guard rearMinimumX >= -0.001, rearMaximumX <= size + 0.001,
                  rearMinimumY >= -0.001, rearMaximumY <= size + 0.001 else {
                throw BubbleLabError.capture("the small symbol's rear contour stroke must stay inside its notch slot")
            }
        }
        let orbitAngles = (0..<8).map { NotchSignalMotion.angle(at: Double($0)) }
        guard Set(orbitAngles.map { Int(($0 * 1000).rounded()) }).count == 8 else {
            throw BubbleLabError.capture("the receive glint must travel around the shell instead of staying on one short arc")
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
