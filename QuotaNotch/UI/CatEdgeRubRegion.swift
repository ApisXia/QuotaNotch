// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Read pointer position without relying on mouseMoved delivery to a transparent background.
/// Never moves the cursor, intercepts controls, or installs a global input event monitor.
struct CatEdgeRubRegion: NSViewRepresentable {
    let enabled: Bool
    let hover: (CatSide?) -> Void
    let summon: (CatSide) -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) {
        view.hover = hover; view.summon = summon; view.cancel = cancel
        if view.enabled != enabled { view.enabled = enabled; view.clear(); view.refreshSampling() }
    }
    static func dismantleNSView(_ view: Region, coordinator: ()) { view.detach() }

    final class Region: NSView {
        var enabled = false
        var hover: ((CatSide?) -> Void)?
        var summon: ((CatSide) -> Void)?
        var cancel: (() -> Void)?
        // Injectable inputs exercise the production timer path in the isolated cloud test app.
        var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }
        var pressedButtons: () -> Int = { NSEvent.pressedMouseButtons }
        var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        private var recognizer = CatEdgeRub()
        private var monitor: Any?
        private var timer: Timer?
        private var heldZone: (CatSide, CGRect)?
        private var lastHover: CatSide?
        private var lastPoint: CGPoint?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var shellFrame: CGRect {
            guard let window else { return .zero }
            return window.convertToScreen(convert(bounds, to: nil))
        }
        func clear() {
            recognizer.reset(); heldZone = nil; lastPoint = nil
            setHover(nil)
        }
        private func setHover(_ side: CatSide?) {
            guard lastHover != side else { return }
            lastHover = side; hover?(side)
        }
        func detach() {
            timer?.invalidate(); timer = nil
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            clear()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); detach()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown,
                .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .scrollWheel]) { [weak self] event in
                guard let self, self.enabled, event.window === self.window else { return event }
                self.clear(); self.cancel?()
                return event
            }
            refreshSampling()
        }
        func refreshSampling() {
            timer?.invalidate(); timer = nil
            guard enabled, window != nil else { return }
            schedule(after: 0.05)
        }
        private func schedule(after interval: TimeInterval) {
            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        private func sample() {
            guard enabled, let window else { return }
            let point = pointerLocation(), frame = shellFrame
            defer { if enabled && self.window != nil { schedule(after: frame.insetBy(dx: -48, dy: -20).contains(point) ? 1.0 / 30 : 0.2) } }
            guard window.isVisible, !isHiddenOrHasHiddenAncestor else { clear(); return }
            guard pressedButtons() == 0 else { clear(); cancel?(); return }
            if let heldZone, !heldZone.1.contains(point) { self.heldZone = nil }
            let side = heldZone?.0 ?? CatEdgeRub.side(at: point, frame: frame)
            setHover(side)
            // Layout moving beneath a stationary pointer must never count as rubbing.
            guard point != lastPoint else { return }
            lastPoint = point
            if let result = recognizer.consume(point: point, frame: frame, at: clock()) {
                heldZone = (result, CatEdgeRub.zone(result, frame: frame))
                setHover(result); summon?(result)
            }
        }
        deinit { timer?.invalidate(); if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
