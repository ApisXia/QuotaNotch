// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import SwiftUI

private final class FilePocketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PocketDropTarget: Equatable {
    case pocket
    case action(PocketImageAction)
}

/// One AppKit destination resolves the curved drop regions explicitly. Separate
/// SwiftUI drop targets would have overlapping rectangular bounds for the arcs.
@MainActor
private final class FilePocketHostingView: NSHostingView<FilePocketView> {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let store = FilePocketStore.shared
        guard store.enabled, !store.busy,
              sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            store.dropTarget = nil; return []
        }
        store.dropTarget = target(sender)
        return store.dropTarget == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { FilePocketStore.shared.dropTarget = nil }
    override func draggingEnded(_ sender: NSDraggingInfo) { FilePocketStore.shared.dropTarget = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { target(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let store = FilePocketStore.shared
        defer { store.dropTarget = nil }
        guard let target = target(sender) else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        switch target {
        case .pocket: return store.accept(urls)
        case .action(let action): return store.accept(urls, action: action)
        }
    }
    private func target(_ sender: NSDraggingInfo) -> PocketDropTarget? {
        var p = convert(sender.draggingLocation, from: nil)
        if !isFlipped { p.y = bounds.height - p.y }
        if CGRect(x: 18, y: 100, width: 112, height: 125).contains(p) { return .pocket }
        if FilePocketStore.shared.expanded {
            return CGRect(x: 146, y: 82, width: 288, height: 274).contains(p) ? .pocket : nil
        }
        for (index, action) in PocketImageAction.allCases.enumerated() {
            let shape = PocketSectorShape(angle: Double(index - 1) * 40)
            if shape.path(in: CGRect(x: 36, y: 23, width: 276, height: 276)).contains(p) { return .action(action) }
        }
        return nil
    }
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
            let content = FilePocketHostingView(rootView: FilePocketView(store: .shared))
            content.registerForDraggedTypes([.fileURL])
            p.contentView = content
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
            if let panel, panel.isVisible {
                // A press that started on our controls keeps receiving its drag
                // and mouse-up even when the pointer stretches outside the shape.
                if event.type == .leftMouseDragged, event.window === panel { return }
                panel.ignoresMouseEvents = !interactivePoint(NSEvent.mouseLocation)
            }
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
