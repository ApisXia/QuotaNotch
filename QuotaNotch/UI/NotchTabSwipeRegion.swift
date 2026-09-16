// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Observe scrolls over the entire visible header row; never intercept button hit testing.
struct NotchTabSwipeRegion: NSViewRepresentable {
    let select: (Int) -> Void
    func makeNSView(context: Context) -> Region { let view = Region(); view.select = select; return view }
    func updateNSView(_ view: Region, context: Context) { view.select = select }

    final class Region: NSView {
        var select: ((Int) -> Void)?
        private var monitor: Any?
        private var navigation = TabSwipeNavigation()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            navigation.reset()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            let phase: TabSwipeNavigation.Phase
            if event.phase.contains(.began) { phase = .began }
            else if event.phase.contains(.cancelled) { phase = .cancelled }
            else if event.phase.contains(.ended) { phase = .ended }
            else if event.phase.contains(.changed) { phase = .changed }
            else { phase = .none }
            let consumed = handleScroll(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                at: event.timestamp, phase: phase, precise: event.hasPreciseScrollingDeltas,
                momentum: !event.momentumPhase.isEmpty, eventWindow: event.window, location: event.locationInWindow)
            return consumed ? nil : event
        }
        @discardableResult
        func handleScroll(x: Double, y: Double, at time: Double, phase: TabSwipeNavigation.Phase,
                          precise: Bool = true, momentum: Bool = false,
                          eventWindow: NSWindow?, location: NSPoint) -> Bool {
            guard let window, window === eventWindow, window.isVisible, !isHiddenOrHasHiddenAncestor,
                  bounds.width > 0, bounds.height > 0,
                  bounds.contains(convert(location, from: nil)),
                  visibleRect.contains(convert(location, from: nil)) else {
                navigation.reset(); return false
            }
            if momentum { return navigation.claimed }
            let wasClaimed = navigation.claimed
            if let step = navigation.consume(x: x, y: y, at: time, phase: phase, precise: precise) {
                select?(step)
            }
            return navigation.claimed || wasClaimed
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
