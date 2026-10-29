// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// A transparent, click-through AppKit bridge for a complete notch wing.
/// It observes scroll-wheel events without becoming the target of clicks or
/// mouse drags, which keeps the existing module buttons intact.
struct NotchHorizontalScrollBridge: NSViewRepresentable {
    let allowsVerticalPassthrough: Bool
    let onHorizontalSwipe: (Bool) -> Void

    init(allowsVerticalPassthrough: Bool = false,
         onHorizontalSwipe: @escaping (Bool) -> Void) {
        self.allowsVerticalPassthrough = allowsVerticalPassthrough
        self.onHorizontalSwipe = onHorizontalSwipe
    }

    func makeNSView(context: Context) -> NotchScrollEventView {
        let view = NotchScrollEventView(frame: .zero,
                                        allowsVerticalPassthrough: allowsVerticalPassthrough)
        view.onHorizontalSwipe = onHorizontalSwipe
        return view
    }

    func updateNSView(_ view: NotchScrollEventView, context: Context) {
        view.allowsVerticalPassthrough = allowsVerticalPassthrough
        view.onHorizontalSwipe = onHorizontalSwipe
    }
}

/// Shared AppKit event routing for notch module pairs. The monitor is local to the app and checks the real view
/// bounds before claiming an event, including non-windowed events delivered by
/// a nonactivating Notch panel.
class NotchScrollEventView: NSView {
    var allowsVerticalPassthrough: Bool
    var onHorizontalSwipe: ((Bool) -> Void)?

    private var monitor: Any?
    private var router = NotchScrollRouter()

    var hasLocalMonitorForPreview: Bool { monitor != nil }
    var currentAxisForPreview: NotchScrollAxis? { router.axis }

    init(frame frameRect: NSRect, allowsVerticalPassthrough: Bool = false) {
        self.allowsVerticalPassthrough = allowsVerticalPassthrough
        super.init(frame: frameRect)
    }

    override init(frame frameRect: NSRect) {
        self.allowsVerticalPassthrough = false
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.allowsVerticalPassthrough = false
        super.init(coder: coder)
    }

    /// The bridge must never steal a button click or a mouse drag.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        installMonitor()
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// Production local-monitor entry point. It delegates to the same
    /// coordinate-aware helper used by the native preview verifier.
    func handle(_ event: NSEvent) -> NSEvent? {
        let consumed = handleScroll(x: event.scrollingDeltaX,
                                    y: event.scrollingDeltaY,
                                    at: event.timestamp,
                                    phase: Self.scrollPhase(for: event),
                                    momentum: !event.momentumPhase.isEmpty,
                                    eventWindow: event.window,
                                    location: event.locationInWindow)
        return consumed ? nil : event
    }

    /// Routes one event using a real target window and point. Keeping this
    /// internal method public to the app target lets cloud fixtures verify the
    /// production bridge without manufacturing CGEvents or calling a bare
    /// reducer/closure.
    @discardableResult
    func handleScroll(x: CGFloat, y: CGFloat, at time: TimeInterval,
                      phase: NotchScrollPhase,
                      momentum: Bool = false,
                      eventWindow: NSWindow?, location: NSPoint) -> Bool {
        guard let targetWindow = window,
              targetWindow.isVisible,
              !isHiddenOrHasHiddenAncestor,
              alphaValue > 0,
              let point = point(forWindow: targetWindow, eventWindow: eventWindow,
                                location: location),
              bounds.width > 0, bounds.height > 0,
              bounds.contains(point), visibleRect.contains(point) else {
            router.reset()
            return false
        }

        let decision = router.update(deltaX: x, deltaY: y, phase: phase,
                                     isMomentum: momentum, timestamp: time,
                                     allowVertical: allowsVerticalPassthrough)
        switch decision {
        case .horizontal(let towardLeft):
            onHorizontalSwipe?(towardLeft)
            return true
        case .consume:
            return true
        case .passthrough, .ended:
            return false
        case .vertical:
            return !allowsVerticalPassthrough
        }
    }

    /// Routes a sample for SETTINGS_PREVIEW and tests without posting a
    /// synthetic global event. This is the same reducer used by `route(event:)`.
    @discardableResult
    func routePreviewScroll(deltaX: CGFloat, deltaY: CGFloat,
                            phase: NotchScrollPhase,
                            isMomentum: Bool,
                            timestamp: TimeInterval) -> NotchScrollRoute {
        let decision = router.update(deltaX: deltaX, deltaY: deltaY,
                                     phase: phase, isMomentum: isMomentum,
                                     timestamp: timestamp,
                                     allowVertical: allowsVerticalPassthrough)
        if case .horizontal(let towardLeft) = decision {
            onHorizontalSwipe?(towardLeft)
        }
        return decision
    }

    private func point(forWindow targetWindow: NSWindow, eventWindow: NSWindow?,
                       location: NSPoint) -> NSPoint? {
        if let eventWindow {
            guard eventWindow === targetWindow else { return nil }
            return convert(location, from: nil)
        }
        // Local monitors can receive a scroll event without an associated
        // window. AppKit reports that location in screen coordinates. Only
        // accept it when the actual nonactivating target is visible and the
        // point lies in that window's frame; never use the global mouse point
        // as a fallback that could switch an unrelated wing.
        guard let screen = targetWindow.screen,
              screen.frame.contains(location),
              targetWindow.frame.contains(location) else { return nil }
        let windowPoint = targetWindow.convertPoint(fromScreen: location)
        return convert(windowPoint, from: nil)
    }

    static func scrollPhase(for event: NSEvent) -> NotchScrollPhase {
        if event.phase.isEmpty { return .none }
        if event.phase.contains(.began) { return .began }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
        return .changed
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        router.reset()
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
