// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import SwiftUI

private final class FilePocketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FilePocketController: ObservableObject {
    static let shared = FilePocketController()
    static let size = NSSize(width: 460, height: 440)
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    private var panel: FilePocketPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var shift = PocketShiftGesture()
    private var locked = false

    func start() {
        guard permissionTimer == nil else { return }
        refreshMonitoring()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                if granted != self.accessibilityGranted {
                    self.accessibilityGranted = granted
                    self.refreshMonitoring()
                }
            }
        }
    }

    func stop() {
        removeMonitors(); permissionTimer?.invalidate(); permissionTimer = nil
        FilePocketStore.shared.cancel(); hide()
    }

    func setLocked(_ value: Bool) {
        locked = value
        if value { hide() }
        refreshMonitoring()
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refreshMonitoring()
    }

    func refreshMonitoring() {
        removeMonitors()
        guard FilePocketStore.shared.enabled, !locked else { return }
        accessibilityGranted = AXIsProcessTrusted()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .leftMouseDragged]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // NSEvent delivers event-monitor callbacks on the main thread.
            self?.handle(event)
            return event
        }
        if accessibilityGranted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
        }
    }

    func show() {
        guard FilePocketStore.shared.enabled, !locked else { return }
        if panel == nil {
            let p = FilePocketPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = .floating; p.hidesOnDeactivate = false
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false; p.acceptsMouseMovedEvents = true
            p.contentView = NSHostingView(rootView: FilePocketView(store: .shared).environment(\.locale, QuotaLanguage.locale))
            panel = p
        }
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        // The upright pocket stays under the cursor; expansion does not move it.
        let x = min(max(mouse.x - 74, visible.minX), max(visible.minX, visible.maxX - Self.size.width))
        let y = min(max(mouse.y - (Self.size.height - 161), visible.minY), max(visible.minY, visible.maxY - Self.size.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.ignoresMouseEvents = false
        if NSEvent.pressedMouseButtons & 1 != 0 { panel.orderFrontRegardless() }
        else { panel.makeKeyAndOrderFront(nil) }
    }

    func hide() { panel?.orderOut(nil); shift.reset() }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; shift.reset()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let other = !flags.intersection([.command, .control, .option, .function]).isEmpty
            if shift.update(shift: flags.contains(.shift), otherModifier: other, at: event.timestamp) {
                if panel?.isVisible == true, NSEvent.pressedMouseButtons == 0 { hide() } else { show() }
            }
        case .keyDown:
            shift.reset()
            if event.keyCode == 53 { hide() }
        case .leftMouseDown, .rightMouseDown:
            shift.reset()
            if let panel, panel.isVisible, !interactivePoint(NSEvent.mouseLocation) { hide() }
        case .mouseMoved, .leftMouseDragged:
            if let panel, panel.isVisible { panel.ignoresMouseEvents = !interactivePoint(NSEvent.mouseLocation) }
        default: break
        }
    }

    private func interactivePoint(_ screenPoint: NSPoint) -> Bool {
        guard let panel else { return false }
        let p = NSPoint(x: screenPoint.x - panel.frame.minX, y: panel.frame.maxY - screenPoint.y)
        // Clear portions of the floating window pass through to the desktop.
        if CGRect(x: 8, y: 88, width: 130, height: 156).contains(p) { return true }
        if CGRect(x: 26, y: 364, width: 408, height: 58).contains(p) { return true }
        if FilePocketStore.shared.expanded { return CGRect(x: 140, y: 76, width: 304, height: 282).contains(p) }
        let dx = p.x - 174, dy = p.y - 161, radius = hypot(dx, dy)
        return radius >= 68 && radius <= 148 && abs(atan2(dy, dx)) <= .pi / 3 + 0.08
    }
}
