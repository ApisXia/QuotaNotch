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
        // fixture constants. This catches a transparent overlay or a shifted
        // full-wing frame that would otherwise make the reducer appear valid.
        let leftPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.midX,
                                                    y: shelfBridge.bounds.midY), to: nil)
        let rightPoint = rightBridge.convert(NSPoint(x: rightBridge.bounds.midX,
                                                     y: rightBridge.bounds.midY), to: nil)
        var timestamp = 1.0

        // Slow trackpad samples must accumulate across the gesture. A second
        // pair of samples in the opposite direction proves the bridge is not
        // hard-coded to one side.
        _ = shelfBridge.handleScroll(x: -2, y: 0, at: timestamp, phase: .none,
                                     eventWindow: window, location: leftPoint)
        timestamp += 0.05
        _ = shelfBridge.handleScroll(x: -2, y: 0, at: timestamp, phase: .none,
                                     eventWindow: window, location: leftPoint)
        timestamp += 0.05
        _ = shelfBridge.handleScroll(x: -2, y: 0, at: timestamp, phase: .none,
                                     eventWindow: window, location: leftPoint)
        timestamp += 0.05
        _ = shelfBridge.handleScroll(x: 0, y: 0, at: timestamp, phase: .ended,
                                     eventWindow: window, location: leftPoint)

        let leftCountBeforeRight = leftActions.count
        timestamp = 2.0
        _ = rightBridge.handleScroll(x: 2, y: 0, at: timestamp, phase: .none,
                                     eventWindow: window, location: rightPoint)
        timestamp += 0.05
        _ = rightBridge.handleScroll(x: 2, y: 0, at: timestamp, phase: .none,
                                     eventWindow: window, location: rightPoint)
        timestamp += 0.05
        _ = rightBridge.handleScroll(x: 2, y: 0, at: timestamp, phase: .none,
                                     eventWindow: window, location: rightPoint)
        timestamp += 0.05
        _ = rightBridge.handleScroll(x: 0, y: 0, at: timestamp, phase: .ended,
                                     eventWindow: window, location: rightPoint)
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
            _ = shelfBridge.handleScroll(x: delta, y: 0, at: timestamp, phase: .none,
                                         eventWindow: window, location: leftPoint)
            timestamp += 0.05
        }
        _ = shelfBridge.handleScroll(x: 0, y: 0, at: timestamp, phase: .ended,
                                     eventWindow: window, location: leftPoint)
        guard activity.compactExpanded else {
            throw failure("Left-wing scroll changed the right quota/task layout")
        }

        let leftCountBeforeFinalRight = leftActions.count
        timestamp = 2.8
        for delta in [CGFloat(-2), CGFloat(-2), CGFloat(-2)] {
            _ = rightBridge.handleScroll(x: delta, y: 0, at: timestamp, phase: .none,
                                         eventWindow: window, location: rightPoint)
            timestamp += 0.05
        }
        _ = rightBridge.handleScroll(x: 0, y: 0, at: timestamp, phase: .ended,
                                     eventWindow: window, location: rightPoint)
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
        let verticalFirst = shelfBridge.handleScroll(x: 0, y: 2, at: timestamp, phase: .began,
                                                     eventWindow: window, location: leftPoint)
        timestamp += 0.05
        let verticalSecond = shelfBridge.handleScroll(x: 0, y: 3, at: timestamp, phase: .changed,
                                                      eventWindow: window, location: leftPoint)
        timestamp += 0.05
        let horizontalTail = shelfBridge.handleScroll(x: -9, y: 0, at: timestamp, phase: .changed,
                                                      eventWindow: window, location: leftPoint)
        timestamp += 0.05
        _ = shelfBridge.handleScroll(x: 0, y: 0, at: timestamp, phase: .ended,
                                     eventWindow: window, location: leftPoint)
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

        let shelfDownPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.18,
                                                         y: shelfBridge.bounds.midY), to: nil)
        let shelfDragPoint = shelfBridge.convert(NSPoint(x: shelfBridge.bounds.width * 0.28,
                                                         y: shelfBridge.bounds.midY + 1), to: nil)
        if let down = mouseEvent(.leftMouseDown, location: shelfDownPoint, window: window,
                                 timestamp: 5, number: 3),
           let drag = mouseEvent(.leftMouseDragged, location: shelfDragPoint, window: window,
                                 timestamp: 5.05, number: 4),
           let up = mouseEvent(.leftMouseUp, location: shelfDragPoint, window: window,
                               timestamp: 5.1, number: 5) {
            window.sendEvent(down); window.sendEvent(drag); window.sendEvent(up)
        }
        guard exportRequests == 1 else {
            throw failure("Shelf mouse drag did not remain an export gesture")
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
