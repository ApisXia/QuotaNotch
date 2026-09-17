// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// A passive observer attached to the painted shell, before its horizontal offset.
/// Uses only this window's events, leaves clicks/scrolls untouched, and needs no input permission.
struct CatEdgeRubRegion: NSViewRepresentable {
    let enabled: Bool
    let hover: (CatSide?) -> Void
    let summon: (CatSide) -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) {
        view.hover = hover; view.summon = summon; view.cancel = cancel
        if view.enabled != enabled { view.enabled = enabled; view.clear(); view.updateTrackingAreas() }
    }
    static func dismantleNSView(_ view: Region, coordinator: ()) { view.detach() }

    final class Region: NSView {
        var enabled = false
        var hover: ((CatSide?) -> Void)?
        var summon: ((CatSide) -> Void)?
        var cancel: (() -> Void)?
        private var recognizer = CatEdgeRub()
        private var monitor: Any?
        private var tracking: NSTrackingArea?
        private var heldZone: (CatSide, CGRect)?
        private var lastHover: CatSide?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        private var screenFrame: CGRect {
            guard let window else { return .zero }
            return window.convertToScreen(convert(bounds, to: nil))
        }
        func clear() {
            recognizer.reset(); heldZone = nil
            setHover(nil)
        }
        private func setHover(_ side: CatSide?) {
            guard lastHover != side else { return }
            lastHover = side; hover?(side)
        }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            clear()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); detach()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown,
                .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
                self?.observe(event)
                return event
            }
            updateTrackingAreas()
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking); self.tracking = nil }
            guard enabled else { return }
            let area = NSTrackingArea(rect: bounds.insetBy(dx: -20, dy: -6),
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self, userInfo: nil)
            addTrackingArea(area); tracking = area
        }
        override func mouseMoved(with event: NSEvent) { observe(event) }
        override func mouseExited(with event: NSEvent) {
            // Geometry-generated enter/exit events never contribute a stroke.
            if !screenFrame.insetBy(dx: -20, dy: -6).contains(NSEvent.mouseLocation) { clear() }
        }
        func observe(_ event: NSEvent) {
            guard enabled, let window, window === event.window, window.isVisible,
                  !isHiddenOrHasHiddenAncestor else { clear(); return }
            guard event.type == .mouseMoved, NSEvent.pressedMouseButtons == 0 else {
                clear(); cancel?(); return
            }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let frame = screenFrame
            if let heldZone, !heldZone.1.contains(point) { self.heldZone = nil }
            let side = heldZone?.0 ?? CatEdgeRub.side(at: point, frame: frame)
            setHover(side)
            if let result = recognizer.consume(point: point, frame: frame, at: event.timestamp) {
                heldZone = (result, CatEdgeRub.zone(result, frame: frame).union(
                    CGRect(x: point.x - 12, y: frame.minY - 6, width: 24, height: frame.height + 12)))
                setHover(result); summon?(result)
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
