// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum NotchScrollAxis: Equatable { case horizontal, vertical }
enum NotchScrollPhase { case none, began, changed, ended }

enum NotchScrollRoute: Equatable {
    case passthrough
    case consume
    case vertical
    case horizontal(towardLeft: Bool)
    case ended
}

/// A single reducer for both left and right notch-wing switches.
///
/// Trackpads often emit several sub-threshold samples and may begin with a
/// zero delta. The old right-wing monitor tested each sample in isolation,
/// which made a careful swipe appear to do nothing. This reducer claims the
/// first dominant axis, accumulates that axis until five points, and holds
/// the claim through momentum and diagonal tails until the gesture ends.
struct NotchScrollRouter {
    private(set) var axis: NotchScrollAxis?
    private(set) var accumulatedHorizontal: CGFloat = 0
    private var horizontalActionSent = false
    private var lastSampleTimestamp: TimeInterval?
    private var lastActionTimestamp: TimeInterval = -.greatestFiniteMagnitude

    static let gestureGap: TimeInterval = 0.45
    static let axisRatio: CGFloat = 1.2
    static let actionThreshold: CGFloat = 5

    mutating func reset() {
        axis = nil
        accumulatedHorizontal = 0
        horizontalActionSent = false
        lastSampleTimestamp = nil
    }

    /// Routes a sample. The returned route is intentionally independent of
    /// AppKit event delivery so the same exact logic can be exercised by the
    /// native preview verifier and by unit tests.
    mutating func update(deltaX: CGFloat, deltaY: CGFloat,
                         phase: NotchScrollPhase,
                         isMomentum: Bool,
                         timestamp: TimeInterval,
                         allowVertical: Bool = true) -> NotchScrollRoute {
        // Axis ownership is identical on both wings; the bridge decides
        // whether a locked vertical sample is passed to a child receiver.
        _ = allowVertical
        if phase == .began {
            reset()
        }
        if phase == .ended {
            reset()
            return .ended
        }

        if phase == .none,
           let lastSampleTimestamp,
           timestamp - lastSampleTimestamp >= Self.gestureGap {
            reset()
        }
        lastSampleTimestamp = timestamp

        if let axis {
            switch axis {
            case .horizontal:
                // Momentum is part of the same physical gesture. Keep it
                // consumed so it cannot reach the nested vertical receiver.
                guard !horizontalActionSent,
                      !isMomentum else { return .consume }
                accumulatedHorizontal += deltaX
                if abs(accumulatedHorizontal) >= Self.actionThreshold,
                   timestamp - lastActionTimestamp >= Self.gestureGap {
                    horizontalActionSent = true
                    lastActionTimestamp = timestamp
                    return .horizontal(towardLeft: accumulatedHorizontal < 0)
                }
                return .consume
            case .vertical:
                // The child receives vertical samples, including the end of
                // the trackpad's momentum. A later X tail cannot re-claim;
                // consume that tail at the outer bridge instead.
                return (abs(deltaX) > abs(deltaY) * Self.axisRatio)
                    ? .consume : .vertical
            }
        }

        // A momentum sample cannot start a new action, but it is harmless to
        // pass through when no axis has been claimed yet.
        guard !isMomentum else { return .passthrough }

        if abs(deltaX) > abs(deltaY) * Self.axisRatio, abs(deltaX) > 0 {
            axis = .horizontal
            accumulatedHorizontal = deltaX
            if abs(accumulatedHorizontal) >= Self.actionThreshold,
               timestamp - lastActionTimestamp >= Self.gestureGap {
                horizontalActionSent = true
                lastActionTimestamp = timestamp
                return .horizontal(towardLeft: accumulatedHorizontal < 0)
            }
            return .consume
        }
        if abs(deltaY) > abs(deltaX) * Self.axisRatio,
           abs(deltaY) > 0 {
            axis = .vertical
            return .vertical
        }
        return .passthrough
    }
}

