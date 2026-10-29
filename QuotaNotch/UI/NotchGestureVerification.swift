// SPDX-License-Identifier: GPL-3.0-only
#if SETTINGS_PREVIEW
import AppKit
import SwiftUI

/// Cloud-only verification of the production quota/task scroll bridge.
@MainActor
enum NotchGestureVerification {
    static func run() throws {
        let activity = AgentActivityStore.shared
        let oldEnabled = activity.enabled
        let oldExpanded = activity.compactExpanded
        let oldSessions = activity.sessions
        var task = AgentSession(id: "gesture-fixture")
        task.state = .running
        task.title = "Gesture verification"
        task.projectName = "QuotaNotch"
        task.projectRoot = "/tmp/QuotaNotch"
        task.cwd = task.projectRoot
        task.turnID = "fixture"
        task.updatedAt = Date()
        activity.enabled = true
        activity.configurePreview([task])
        activity.compactExpanded = false
        defer {
            activity.configurePreview(oldSessions)
            activity.compactExpanded = oldExpanded
            activity.enabled = oldEnabled
        }
        var clicks = 0
        let root = AgentCompactDock(primaryWidth: 26, height: 38,
                                    anchorWidth: 26, widgetWidth: 26, open: { clicks += 1 }) {
            Color.clear.frame(width: 26, height: 38)
        }.frame(width: 90, height: 38)
        let host = NSHostingView(rootView: root)
        let window = BoringNotchWindow(contentRect: NSRect(x: 240, y: 220, width: 90, height: 38),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        settle()
        host.layoutSubtreeIfNeeded()
        settle()
        guard let bridge = descendants(host).compactMap({ $0 as? NotchScrollEventView }).first,
              bridge.bounds.width >= 40, bridge.hasLocalMonitorForPreview,
              !window.canBecomeKey, !window.canBecomeMain else {
            throw failure("Production bridge missing from nonactivating panel")
        }
        func point(_ fraction: CGFloat) -> NSPoint {
            bridge.convert(NSPoint(x: bridge.bounds.width * fraction, y: bridge.bounds.midY), to: nil)
        }
        func sample(_ x: CGFloat, _ y: CGFloat, _ time: TimeInterval,
                    phase: NotchScrollPhase = .changed, momentum: Bool = false,
                    location: NSPoint? = nil, windowed: Bool = true) -> Bool {
            bridge.handleScroll(x: x, y: y, at: time, phase: phase,
                                momentum: momentum, eventWindow: windowed ? window : nil,
                                location: location ?? point(0.8))
        }
        for fraction: CGFloat in [0.1, 0.5, 0.9] {
            let time = Double(fraction) * 20 + 1
            activity.compactExpanded = false
            settle()
            let target = point(fraction)
            _ = sample(2, 0, time, phase: .began, location: target)
            _ = sample(2, 0, time + 0.05, location: target)
            guard sample(2, 0, time + 0.1, location: target), activity.compactExpanded else {
                throw failure("Slow swipe did not expand tasks across the entire wing")
            }
            _ = sample(-20, 0, time + 0.15, location: target)
            _ = sample(-20, 0, time + 0.2, momentum: true, location: target)
            guard activity.compactExpanded else { throw failure("One gesture switched twice") }
            _ = sample(0, 0, time + 0.25, phase: .ended, location: target)
            settle()
            _ = sample(-8, 0, time + 0.8, phase: .began, location: point(fraction))
            guard !activity.compactExpanded else { throw failure("Reverse swipe did not restore quota") }
            _ = sample(0, 0, time + 0.9, phase: .ended)
        }
        _ = sample(0, 5, 30, phase: .began)
        _ = sample(12, 0, 30.1)
        guard !activity.compactExpanded else { throw failure("Vertical gesture switched modules") }
        _ = sample(0, 0, 30.2, phase: .ended)
        let outside = bridge.convert(NSPoint(x: bridge.bounds.maxX + 50, y: 10), to: nil)
        guard !sample(10, 0, 31, phase: .began, location: outside), !activity.compactExpanded else {
            throw failure("Out-of-bounds event switched modules")
        }
        let screenPoint = window.convertPoint(toScreen: point(0.8))
        _ = sample(8, 0, 32, phase: .began, location: screenPoint, windowed: false)
        guard activity.compactExpanded else { throw failure("Windowless event failed coordinate conversion") }
        _ = sample(0, 0, 32.1, phase: .ended)
        settle()
        guard bridge.hitTest(.zero) == nil else { throw failure("Scroll bridge intercepted clicks") }
        let clickPoint = point(0.9)
        for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
            guard let event = NSEvent.mouseEvent(with: type, location: clickPoint,
                                                 modifierFlags: [], timestamp: 33 + Double(index) * 0.01,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: index, clickCount: 1,
                                                 pressure: index == 0 ? 1 : 0) else {
                throw failure("Could not create click fixture")
            }
            window.sendEvent(event)
        }
        guard clicks == 1 else { throw failure("Task click was blocked by scroll routing") }
        print("Verified production quota/task wing: slow/reverse swipes, whole-wing coverage, momentum, axis lock, bounds, windowless coordinates and clicks")
    }
    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants($0) }
    }
    private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.06)) }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NotchGestureVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
