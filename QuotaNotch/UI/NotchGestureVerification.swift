// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

#if SETTINGS_PREVIEW
/// Native preview verification for the two full-wing scroll bridges. This is
/// intentionally kept separate from SettingsPreviewRunner so the runner can
/// choose when to register it without duplicating fixture layout code.
@MainActor
enum NotchGestureVerification {
    static func run() throws {
        var leftActions: [Bool] = []
        var rightActions: [Bool] = []
        var audioClicks = 0
        var exportRequests = 0

        // Use the production AgentCompactDock on the right side. The fixture
        // must prove that the shared bridge changes the real compactExpanded
        // state, rather than toggling a test-only rectangle.
        let activity = AgentActivityStore.shared
        let previousEnabled = activity.enabled
        let previousExpanded = activity.compactExpanded
        let previousSessions = activity.sessions
        var activityFixture = AgentSession(id: "notch-gesture-verification")
        activityFixture.state = .running
        activityFixture.title = "Notch gesture verification"
        activityFixture.projectName = "QuotaNotch"
        activityFixture.projectRoot = "/tmp/QuotaNotch"
        activityFixture.cwd = activityFixture.projectRoot
        activityFixture.turnID = "fixture"
        activityFixture.updatedAt = Date()
        activity.enabled = true
        activity.configurePreview([activityFixture])
        activity.compactExpanded = false
        defer {
            activity.configurePreview(previousSessions)
            activity.compactExpanded = previousExpanded
            activity.enabled = previousEnabled
        }

        let state = BubbleShelfCompactState(
            itemCount: 2,
            isReceiving: false,
            onOpen: {},
            onVerticalSwipe: { _ in },
            writers: {
                exportRequests += 1
                return []
            },
            onHorizontalSwipe: { leftActions.append($0) }
        )
        let root = NotchGestureVerificationSurface(
            shelf: state,
            onAudioOpen: { audioClicks += 1 },
            onLeftSwap: { leftActions.append($0) }
        )
        let size = NSSize(width: 150, height: 38)
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
        let window = BoringNotchWindow(
            contentRect: NSRect(origin: NSPoint(x: 240, y: 220), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        settle()
        host.layoutSubtreeIfNeeded()
        settle()
        guard !window.canBecomeKey, !window.canBecomeMain else {
            throw failure("Gesture fixture used an activating window")
        }

        let shelfBridge = descendants(of: host).compactMap { $0 as? BubbleShelfHorizontalScrollView }.first
        let rightBridge = descendants(of: host).compactMap { $0 as? NotchScrollEventView }
            .first { !($0 is BubbleShelfHorizontalScrollView) }
        guard let shelfBridge, let rightBridge,
              shelfBridge.bounds.width >= 50,
              rightBridge.bounds.width >= 40,
              shelfBridge.window === window,
              rightBridge.window === window,
              shelfBridge.hasLocalMonitorForPreview,
              rightBridge.hasLocalMonitorForPreview else {
            throw failure("Full-wing scroll bridges did not install inside the nonactivating Notch window")
        }

        // Derive event points from the actual bridge bounds rather than from
        // fixture constants. Use both ends of each real wing: a transparent
        // overlay or shifted frame must not make the reducer appear valid at
        // only one convenient midpoint.
        let leftLeadingPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.18,
                                                           y: shelfBridge.bounds.midY), to: nil)
        let leftTrailingPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.82,
                                                            y: shelfBridge.bounds.midY), to: nil)
        let rightLeadingPoint = rightBridge.convert(NSPoint(x: rightBridge.bounds.width * 0.18,
                                                            y: rightBridge.bounds.midY), to: nil)
        let rightTrailingPoint = rightBridge.convert(NSPoint(x: rightBridge.bounds.width * 0.82,
                                                             y: rightBridge.bounds.midY), to: nil)

        // AppKit sends the same local scroll event through every installed
        // monitor. Offer each sample to both production bridges so only the
        // bridge whose actual bounds contain the event can consume or act.
        func routeBoth(x: CGFloat, y: CGFloat, at time: TimeInterval,
                       phase: BubbleScrollPhase, momentum: Bool = false,
                       location: NSPoint) -> (left: Bool, right: Bool) {
            let left = shelfBridge.handleScroll(x: x, y: y, at: time, phase: phase,
                                                momentum: momentum, eventWindow: window,
                                                location: location)
            let right = rightBridge.handleScroll(x: x, y: y, at: time, phase: phase,
                                                 momentum: momentum, eventWindow: window,
                                                 location: location)
            return (left, right)
        }
        var timestamp = 1.0

        // Slow trackpad samples must accumulate across the gesture. A second
        // pair of samples in the opposite direction proves the bridge is not
        // hard-coded to one side.
        var routed = routeBoth(x: -2, y: 0, at: timestamp, phase: .none,
                               location: leftLeadingPoint)
        guard routed.left, !routed.right else {
            throw failure("Left-wing event was consumed by the wrong bridge")
        }
        timestamp += 0.05
        routed = routeBoth(x: -2, y: 0, at: timestamp, phase: .none,
                           location: leftLeadingPoint)
        guard routed.left, !routed.right else {
            throw failure("Left-wing event was consumed by the wrong bridge")
        }
        timestamp += 0.05
        routed = routeBoth(x: -2, y: 0, at: timestamp, phase: .none,
                           location: leftLeadingPoint)
        guard routed.left, !routed.right else {
            throw failure("Left-wing event was consumed by the wrong bridge")
        }
        timestamp += 0.05
        _ = routeBoth(x: 0, y: 0, at: timestamp, phase: .ended,
                      location: leftLeadingPoint)

        let leftCountBeforeRight = leftActions.count
        timestamp = 2.0
        routed = routeBoth(x: 2, y: 0, at: timestamp, phase: .none,
                           location: rightTrailingPoint)
        guard !routed.left, routed.right else {
            throw failure("Right-wing event was consumed by the wrong bridge")
        }
        timestamp += 0.05
        routed = routeBoth(x: 2, y: 0, at: timestamp, phase: .none,
                           location: rightTrailingPoint)
        guard !routed.left, routed.right else {
            throw failure("Right-wing event was consumed by the wrong bridge")
        }
        timestamp += 0.05
        routed = routeBoth(x: 2, y: 0, at: timestamp, phase: .none,
                           location: rightTrailingPoint)
        guard !routed.left, routed.right else {
            throw failure("Right-wing event was consumed by the wrong bridge")
        }
        timestamp += 0.05
        _ = routeBoth(x: 0, y: 0, at: timestamp, phase: .ended,
                      location: rightTrailingPoint)
        guard activity.compactExpanded else {
            throw failure("Right-wing production dock did not expand after a rightward scroll")
        }
        guard leftActions.count == leftCountBeforeRight else {
            throw failure("Right-wing scroll changed the left Shelf/audio pair")
        }
        rightActions.append(activity.compactExpanded)

        // Repeat from the opposite edge on each same physical wing. The
        // action belongs to the point's pair, never to both bridges at once.
        timestamp = 1.8
        for delta in [CGFloat(2), CGFloat(2), CGFloat(2)] {
            routed = routeBoth(x: delta, y: 0, at: timestamp, phase: .none,
                               location: leftTrailingPoint)
            guard routed.left, !routed.right else {
                throw failure("Left reverse event was consumed by the wrong bridge")
            }
            timestamp += 0.05
        }
        _ = routeBoth(x: 0, y: 0, at: timestamp, phase: .ended,
                      location: leftTrailingPoint)
        guard activity.compactExpanded else {
            throw failure("Left-wing scroll changed the right quota/task layout")
        }

        let leftCountBeforeFinalRight = leftActions.count
        timestamp = 2.8
        for delta in [CGFloat(-2), CGFloat(-2), CGFloat(-2)] {
            routed = routeBoth(x: delta, y: 0, at: timestamp, phase: .none,
                               location: rightLeadingPoint)
            guard !routed.left, routed.right else {
                throw failure("Right reverse event was consumed by the wrong bridge")
            }
            timestamp += 0.05
        }
        _ = routeBoth(x: 0, y: 0, at: timestamp, phase: .ended,
                      location: rightLeadingPoint)
        guard !activity.compactExpanded else {
            throw failure("Right-wing production dock did not compact after a leftward scroll")
        }
        guard leftActions.count == leftCountBeforeFinalRight else {
            throw failure("Right-wing scroll changed the left Shelf/audio pair")
        }
        rightActions.append(activity.compactExpanded)

        guard leftActions.contains(true), leftActions.contains(false),
              rightActions.contains(false), rightActions.contains(true) else {
            throw failure("Both full-wing horizontal directions were not delivered")
        }

        // A vertical-first diagonal must stay with the Shelf receiver. Its
        // later horizontal tail is sent through the same window and must not
        // create a second pair swap.
        let leftCountBeforeVertical = leftActions.count
        timestamp = 3.0
        routed = routeBoth(x: 0, y: 2, at: timestamp, phase: .began,
                           location: leftTrailingPoint)
        let verticalFirst = routed.left
        guard !routed.right else {
            throw failure("Right bridge consumed a left-wing vertical event")
        }
        timestamp += 0.05
        routed = routeBoth(x: 0, y: 3, at: timestamp, phase: .changed,
                           location: leftTrailingPoint)
        let verticalSecond = routed.left
        guard !routed.right else {
            throw failure("Right bridge consumed a left-wing vertical event")
        }
        timestamp += 0.05
        routed = routeBoth(x: -9, y: 0, at: timestamp, phase: .changed,
                           location: leftTrailingPoint)
        let horizontalTail = routed.left
        guard !routed.right else {
            throw failure("Right bridge consumed a left-wing diagonal tail")
        }
        timestamp += 0.05
        _ = routeBoth(x: 0, y: 0, at: timestamp, phase: .ended,
                      location: leftTrailingPoint)
        guard !verticalFirst, !verticalSecond, horizontalTail,
              shelfBridge.currentAxisForPreview == nil,
              leftActions.count == leftCountBeforeVertical else {
            throw failure("Vertical-first diagonal leaked into a horizontal pair swap")
        }

        // Real mouse events still reach the existing child controls. The
        // transparent bridges are not allowed to become the hit-test target.
        let audioPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.78,
                                                     y: shelfBridge.bounds.midY), to: nil)
        guard let audioEventDown = mouseEvent(.leftMouseDown, location: audioPoint,
                                              window: window, timestamp: 4, number: 1),
              let audioEventUp = mouseEvent(.leftMouseUp, location: audioPoint,
                                            window: window, timestamp: 4.01, number: 2) else {
            throw failure("Could not create audio click events")
        }
        window.sendEvent(audioEventDown)
        window.sendEvent(audioEventUp)
        guard audioClicks == 1 else {
            throw failure("Audio click was intercepted by a full-wing scroll bridge")
        }

        let shelfDownPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.05,
                                                         y: shelfBridge.bounds.midY), to: nil)
        // BubbleInteractionView starts an export after an 8pt Euclidean
        // movement. The earlier 18% -> 28% sample was only about 5pt in the
        // real 54pt pair and therefore exercised a click, not a drag.
        let shelfDragPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.28,
                                                         y: shelfBridge.bounds.midY + 1), to: nil)
        let dragHandle = descendants(of: host).first {
            String(describing: type(of: $0)).contains("BubbleInteractionView")
        }
        guard let dragHandle, let dragSuperview = dragHandle.superview else {
            throw failure("Shelf drag handle was not present in the native view tree")
        }
        let downLocal = dragHandle.convert(shelfDownPoint, from: nil)
        let dragLocal = dragHandle.convert(shelfDragPoint, from: nil)
        let downInSuperview = dragHandle.convert(downLocal, to: dragSuperview)
        let dragInSuperview = dragHandle.convert(dragLocal, to: dragSuperview)
        let downHit = dragSuperview.hitTest(downInSuperview)
        let dragHit = dragSuperview.hitTest(dragInSuperview)
        let hitDiagnostic = "handleFrame=\(NSStringFromRect(dragHandle.frame)) down=\(NSStringFromPoint(downLocal)) drag=\(NSStringFromPoint(dragLocal)) downHit=\(String(describing: downHit.map { type(of: $0) })) dragHit=\(String(describing: dragHit.map { type(of: $0) })) exports=\(exportRequests)"
        guard dragHandle.bounds.contains(downLocal), dragHandle.bounds.contains(dragLocal),
              downHit === dragHandle, dragHit === dragHandle else {
            throw failure("Shelf drag hit-test did not resolve to the native handle (\(hitDiagnostic))")
        }
        if let down = mouseEvent(.leftMouseDown, location: shelfDownPoint, window: window,
                                 timestamp: 5, number: 3),
           let drag = mouseEvent(.leftMouseDragged, location: shelfDragPoint, window: window,
                                 timestamp: 5.05, number: 4),
           let up = mouseEvent(.leftMouseUp, location: shelfDragPoint, window: window,
                               timestamp: 5.1, number: 5) {
            window.sendEvent(down); window.sendEvent(drag); window.sendEvent(up)
        }
        guard exportRequests == 1 else {
            throw failure("Shelf mouse drag did not remain an export gesture (\(hitDiagnostic))")
        }

        guard activity.compactExpanded == false else {
            throw failure("Right-wing production dock did not settle back to compact state")
        }

        let report = "Nonactivating Notch window: both real wing bridges changed their production layouts in both directions; vertical axis lock, audio click, and Shelf export drag passed."
        print("NotchGestureVerification: \(report)")
    }

    private static func mouseEvent(_ type: NSEvent.EventType, location: NSPoint,
                                   window: NSWindow, timestamp: TimeInterval,
                                   number: Int) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                           timestamp: timestamp, windowNumber: window.windowNumber,
                           context: nil, eventNumber: number, clickCount: 1,
                           pressure: type == .leftMouseDown ? 1 : 0)
    }

    private static func descendants(of root: NSView) -> [NSView] {
        root.subviews + root.subviews.flatMap { descendants(of: $0) }
    }

    private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NotchGestureVerification", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct NotchGestureVerificationSurface: View {
    let shelf: BubbleShelfCompactState
    let onAudioOpen: () -> Void
    let onLeftSwap: (Bool) -> Void
    @State private var arrangement: BubbleShelfAudioArrangement = .shelfMinimalAudioWidget

    private var routedShelf: BubbleShelfCompactState {
        BubbleShelfCompactState(itemCount: shelf.itemCount,
                                isReceiving: shelf.isReceiving,
                                onOpen: shelf.onOpen,
                                onVerticalSwipe: shelf.onVerticalSwipe,
                                writers: shelf.writers,
                                onHorizontalSwipe: { towardLeft in
                                    arrangement = arrangement.switched(towardLeft: towardLeft)
                                    onLeftSwap(towardLeft)
                                })
    }

    var body: some View {
        HStack(spacing: 24) {
            BubbleShelfAudioPair(shelf: routedShelf,
                                 arrangement: arrangement,
                                 height: 38,
                                 widgetWidth: 26,
                                 onAudioOpen: onAudioOpen)
            AgentCompactDock(primaryWidth: 26, height: 38,
                             anchorWidth: 26, widgetWidth: 26, open: {}) {
                Color.clear.frame(width: 26, height: 38)
            }
        }
        .frame(height: 38)
    }
}
#endif
