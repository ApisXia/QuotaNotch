// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import Combine
import Foundation
import UniformTypeIdentifiers

enum BubbleCollectorAvailability: Equatable {
    case disabled
    case ready
    case accessibilityRequired
    case selectionUnavailable
    case captured
    case error
}

enum BubbleCollectorPayload: Equatable, Identifiable {
    case file(URL)
    case text(String)
    case webURL(URL)
    case stored(BubbleShelfItem)

    var id: String {
        switch self {
        case .file(let url): "file:" + url.standardizedFileURL.path
        case .text(let text): "text:" + BubbleShelfItem.sha256(Data(text.utf8))
        case .webURL(let url): "url:" + url.absoluteString
        case .stored(let item): "stored:" + item.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .file(let url): url.deletingPathExtension().lastPathComponent
        case .text(let text): String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(76))
        case .webURL(let url): url.host ?? url.absoluteString
        case .stored(let item): item.title
        }
    }

    var fileURL: URL? {
        switch self {
        case .file(let url): url
        case .stored(let item): item.fileURL
        case .text, .webURL: nil
        }
    }
}

struct BubbleCollectorSelection: Identifiable {
    let fingerprint: String
    let sourceProcessID: Int32
    let payloads: [BubbleCollectorPayload]
    let omittedCount: Int
    let anchor: CGPoint
    let observedAt: Date
    let generation: UInt64

    var id: String { fingerprint }
}

enum BubbleCollectorPresentation {
    case selection(BubbleCollectorSelection)
    case drag(anchor: CGPoint, generation: UInt64)
    case captured(payloads: [BubbleCollectorPayload], anchor: CGPoint, startedAt: Date, generation: UInt64)
}

@MainActor
final class BubbleCollectorController: ObservableObject {
    static let shared = BubbleCollectorController()

    @Published private(set) var availability: BubbleCollectorAvailability = .disabled
    @Published private(set) var statusMessage: String?
    @Published private(set) var presentation: BubbleCollectorPresentation?

    private let store = BubbleShelfStore.shared
    private let axQueue = DispatchQueue(label: "com.quotanotch.bubble-ax-reader", qos: .userInitiated)
    private var eventMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var pendingSelectionRead: DispatchWorkItem?
    private var expirationTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var previousFingerprint: String?
    private var lastDragPasteboardChangeCount: Int?
    private var panelController: BubbleCollectorFloatingPanel?
    private var isRunning = false
    private var selectionReadRevision: UInt64 = 0
    private var stationaryAnchor: CGPoint?

    private init() {}

    /// Called directly from the explicit receive-mode toggle. This is the only
    /// automatic path allowed to ask macOS to show the Accessibility prompt.
    func startReceivingFromUser() {
        store.isReceiving = true
        generation &+= 1
        #if SETTINGS_PREVIEW
        availability = .disabled
        statusMessage = nil
        return
        #else
        let trusted = Self.requestAccessibilityTrust(prompt: true)
        guard trusted else {
            stopMonitors(clearPresentation: true)
            availability = .accessibilityRequired
            statusMessage = "Allow QuotaNotch in System Settings → Privacy & Security → Accessibility, then choose Retry."
            return
        }
        beginMonitoring()
        #endif
    }

    /// Restores the user's saved mode without prompting at launch.
    func synchronizePersistedMode() {
        guard store.isReceiving else {
            generation &+= 1
            stopMonitors(clearPresentation: true)
            if BubbleCollectorPolicy.shouldPersistPausedStartup(hasBeenConfigured: store.hasBeenConfigured) {
                store.isReceiving = false
            }
            availability = .disabled
            statusMessage = nil
            return
        }
        #if SETTINGS_PREVIEW
        availability = .disabled
        statusMessage = nil
        #else
        guard Self.requestAccessibilityTrust(prompt: false) else {
            stopMonitors(clearPresentation: true)
            availability = .accessibilityRequired
            statusMessage = "Receiving is on, but Accessibility access is needed to detect selections. Choose Retry to continue."
            return
        }
        beginMonitoring()
        #endif
    }

    func pauseReceiving() {
        store.isReceiving = false
        generation &+= 1
        stopMonitors(clearPresentation: true)
        availability = .disabled
        statusMessage = nil
    }

    /// Invoked by a visible retry button, never by launch or background polling.
    func requestAccessibilityFromUserAction() {
        guard store.isReceiving else { return }
        guard Self.requestAccessibilityTrust(prompt: true) else {
            availability = .accessibilityRequired
            statusMessage = "Accessibility access is still off. Enable QuotaNotch in System Settings, then retry."
            return
        }
        beginMonitoring()
    }

    func captureCurrentCandidate() {
        guard store.isReceiving, case .selection(let selection) = presentation,
              selection.generation == generation,
              Date().timeIntervalSince(selection.observedAt) < 18 else {
            hideCandidate()
            return
        }
        let insertionGeneration = generation
        var aggregate = BubbleShelfImportResult()
        // Store inserts at the front, so feed the selected collection in reverse
        // to preserve the accessibility source's order in the shelf.
        for payload in selection.payloads.reversed() {
            guard store.isReceiving, generation == insertionGeneration else { return }
            merge(insert(payload), into: &aggregate)
        }
        store.recordImportResult(aggregate)
        guard aggregate.succeeded else {
            availability = .error
            statusMessage = aggregate.message ?? "This selection could not be added."
            return
        }
        var message = aggregate.message ?? "Added to the shelf."
        if selection.omittedCount > 0 {
            message += "; \(selection.omittedCount) selected item(s) could not be read or exceeded the 80-item batch limit."
        }
        statusMessage = message
        let savedItems = Array(store.items.prefix(4)).map(BubbleCollectorPayload.stored)
        showCaptured(payloads: savedItems, anchor: selection.anchor, generation: insertionGeneration)
    }

    /// A fixture-only entry point. It never queries another process or changes storage.
    func showPreviewForTesting(contents: [BubbleCollectorPayload], anchor: CGPoint) {
        #if SETTINGS_PREVIEW
        generation &+= 1
        let payloads = Array(contents.prefix(4))
        showCaptured(payloads: payloads, anchor: anchor, generation: generation, testFixture: true)
        #endif
    }

    #if SETTINGS_PREVIEW
    /// Injects a frozen candidate into the same panel used by AX selection events.
    /// The preview runner uses this instead of prompting for Accessibility access.
    func showSelectionForTesting(contents: [BubbleCollectorPayload], anchor: CGPoint) {
        generation &+= 1
        let payloads = Array(contents.prefix(80))
        let selection = BubbleCollectorSelection(
            fingerprint: "fixture-" + UUID().uuidString,
            sourceProcessID: 42,
            payloads: payloads,
            omittedCount: 0,
            anchor: anchor,
            observedAt: Date(),
            generation: generation
        )
        presentation = .selection(selection)
        stationaryAnchor = anchor
        statusMessage = "Selection ready. Click the bubble to save it."
        ensurePanelController().present(anchor: anchor)
        scheduleExpiration(for: selection.generation, after: 18)
    }

    func hidePreviewForTesting() {
        hideCandidate()
    }
    #endif

    func shutdown() {
        generation &+= 1
        stopMonitors(clearPresentation: true)
        availability = .disabled
    }

    // MARK: Event ingestion

    private func beginMonitoring() {
        guard !isRunning else {
            availability = .ready
            statusMessage = "Receiving is on. Select text or files, then click the nearby bubble to save."
            return
        }
        isRunning = true
        generation &+= 1
        availability = .ready
        statusMessage = "Receiving is on. Select text or files, then click the nearby bubble to save."
        // Establish a baseline without presenting or importing the current selection.
        previousFingerprint = nil
        lastDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            enqueueSelectionRead(for: app.processIdentifier, bundleID: app.bundleIdentifier, baseline: true)
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in self?.frontmostApplicationChanged(app) }
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .keyUp, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleGlobalEvent(event) }
        }
    }

    private func stopMonitors(clearPresentation: Bool) {
        isRunning = false
        pendingSelectionRead?.cancel()
        pendingSelectionRead = nil
        expirationTask?.cancel()
        expirationTask = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
        previousFingerprint = nil
        lastDragPasteboardChangeCount = nil
        if clearPresentation {
            presentation = nil
            panelController?.hide()
        }
    }

    private func frontmostApplicationChanged(_ app: NSRunningApplication) {
        guard isRunning, store.isReceiving else { return }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // Never leave a preview from a prior application hanging over a new one.
        hideCandidate()
        pendingSelectionRead?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            self.enqueueSelectionRead(for: app.processIdentifier, bundleID: app.bundleIdentifier, baseline: true)
        }
        pendingSelectionRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func handleGlobalEvent(_ event: NSEvent) {
        guard isRunning, store.isReceiving,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if event.type == .leftMouseDragged {
            handleDragPreview(from: frontmost, event: event)
            return
        }
        pendingSelectionRead?.cancel()
        let processID = frontmost.processIdentifier
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.store.isReceiving,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return }
            self.enqueueSelectionRead(for: processID, bundleID: frontmost.bundleIdentifier, baseline: false)
        }
        pendingSelectionRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func enqueueSelectionRead(for processID: pid_t, bundleID: String?, baseline: Bool) {
        selectionReadRevision &+= 1
        let revision = selectionReadRevision
        let expectedGeneration = generation
        let anchor = NSEvent.mouseLocation
        axQueue.async { [weak self] in
            let sample = AXSelectionReader.read(processID: processID, bundleID: bundleID, fallbackAnchor: anchor)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.store.isReceiving,
                      self.generation == expectedGeneration,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return }
                if baseline {
                    guard self.selectionReadRevision == revision else { return }
                    self.previousFingerprint = sample?.fingerprint
                } else {
                    self.applySelectionSample(sample, from: processID)
                }
            }
        }
    }

    private func applySelectionSample(_ sample: AXSelectionSample?, from processID: pid_t) {
        guard let sample else {
            previousFingerprint = nil
            if case .selection = presentation { hideCandidate() }
            availability = .selectionUnavailable
            statusMessage = "This app does not expose a readable text or file selection. Drag supported content into the bubble instead."
            return
        }
        if sample.isSecureField || sample.payloads.isEmpty {
            previousFingerprint = sample.fingerprint
            if case .selection = presentation { hideCandidate() }
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard BubbleCollectorPolicy.shouldPresentSelection(
            receiving: store.isReceiving, sourceProcessID: processID, ownProcessID: ownPID,
            isSecureField: sample.isSecureField, oldFingerprint: previousFingerprint,
            newFingerprint: sample.fingerprint
        ) else {
            previousFingerprint = sample.fingerprint
            return
        }
        previousFingerprint = sample.fingerprint
        generation &+= 1
        let snapshot = BubbleCollectorSelection(
            fingerprint: sample.fingerprint, sourceProcessID: processID,
            payloads: Array(sample.payloads.prefix(80)), omittedCount: sample.omittedCount,
            anchor: sample.anchor ?? NSEvent.mouseLocation,
            observedAt: Date(), generation: generation
        )
        availability = .ready
        statusMessage = sample.omittedCount > 0
            ? "Selection ready. \(sample.omittedCount) item(s) could not be read or exceed the 80-item batch limit. Click the bubble to save the readable items."
            : "Selection ready. Click the bubble to save it."
        presentation = .selection(snapshot)
        stationaryAnchor = snapshot.anchor
        ensurePanelController().present(anchor: snapshot.anchor)
        scheduleExpiration(for: snapshot.generation, after: 18)
    }

    private func handleDragPreview(from application: NSRunningApplication, event: NSEvent) {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard BubbleCollectorPolicy.shouldPreviewDrag(
            receiving: store.isReceiving, sourceProcessID: application.processIdentifier,
            ownProcessID: ProcessInfo.processInfo.processIdentifier,
            pasteboardChanged: changeCount != lastDragPasteboardChangeCount,
            types: types
        ) else { return }
        lastDragPasteboardChangeCount = changeCount
        generation &+= 1
        let anchor = stationaryAnchor ?? NSEvent.mouseLocation
        presentation = .drag(anchor: anchor, generation: generation)
        stationaryAnchor = anchor
        statusMessage = "Drop supported content into the bubble to save it."
        ensurePanelController().present(anchor: anchor)
        scheduleExpiration(for: generation, after: 10)
        _ = event
    }

    func receiveDrop(_ pasteboard: NSPasteboard, sourceProcessID: Int32) -> Bool {
        guard store.isReceiving, sourceProcessID != ProcessInfo.processInfo.processIdentifier,
              pasteboardHasSupportedContent(pasteboard) else { return false }
        let insertionGeneration = generation
        let result = store.importPasteboardManually(pasteboard)
        guard store.isReceiving, generation == insertionGeneration else { return false }
        guard result.succeeded else {
            availability = .error
            statusMessage = result.message ?? "That content could not be added."
            return false
        }
        statusMessage = result.message ?? "Added to the shelf."
        let anchor: CGPoint
        if case .drag(let point, _) = presentation { anchor = point }
        else { anchor = stationaryAnchor ?? NSEvent.mouseLocation }
        let newItems = Array(store.items.prefix(4)).map(BubbleCollectorPayload.stored)
        showCaptured(payloads: newItems, anchor: anchor, generation: insertionGeneration)
        return true
    }

    private func pasteboardHasSupportedContent(_ pasteboard: NSPasteboard) -> Bool {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        return !types.isDisjoint(with: BubbleCollectorPolicy.supportedDragTypes)
    }

    private func insert(_ payload: BubbleCollectorPayload) -> BubbleShelfImportResult {
        switch payload {
        case .file(let url): store.addFile(url)
        case .text(let text): store.addText(text)
        case .webURL(let url): store.addURL(url)
        case .stored(let item):
            switch item.kind {
            case .file, .folder: item.fileURL.map(store.addFile) ?? BubbleShelfImportResult()
            case .text: item.text.map(store.addText) ?? BubbleShelfImportResult()
            case .url: item.resourceURL.map(store.addURL) ?? BubbleShelfImportResult()
            case .image: BubbleShelfImportResult()
            }
        }
    }

    private func merge(_ next: BubbleShelfImportResult, into aggregate: inout BubbleShelfImportResult) {
        aggregate.addedCount += next.addedCount
        aggregate.duplicateCount += next.duplicateCount
        aggregate.skippedCount += next.skippedCount
        aggregate.errors.append(contentsOf: next.errors)
    }

    private func showCaptured(payloads: [BubbleCollectorPayload], anchor: CGPoint,
                              generation: UInt64, testFixture: Bool = false) {
        availability = testFixture ? .ready : .captured
        presentation = .captured(payloads: Array(payloads.prefix(4)), anchor: anchor,
                                 startedAt: Date(), generation: generation)
        stationaryAnchor = anchor
        ensurePanelController().present(anchor: anchor)
        scheduleExpiration(for: generation, after: BubbleCollectorMotion.totalDuration + 0.05)
    }

    private func hideCandidate() {
        generation &+= 1
        expirationTask?.cancel()
        presentation = nil
        stationaryAnchor = nil
        panelController?.hide()
        if store.isReceiving { availability = .ready }
    }

    private func scheduleExpiration(for expectedGeneration: UInt64, after delay: TimeInterval) {
        expirationTask?.cancel()
        expirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            self.presentation = nil
            self.stationaryAnchor = nil
            self.panelController?.hide()
            if self.store.isReceiving { self.availability = .ready }
        }
    }

    private func ensurePanelController() -> BubbleCollectorFloatingPanel {
        if let panelController { return panelController }
        let created = BubbleCollectorFloatingPanel(controller: self)
        panelController = created
        return created
    }

    private static func requestAccessibilityTrust(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary)
    }
}

private struct AXSelectionSample {
    let fingerprint: String
    let payloads: [BubbleCollectorPayload]
    let omittedCount: Int
    let anchor: CGPoint?
    let isSecureField: Bool
}

/// Reads only the frontmost app's current selection. No clipboard polling or AppleEvents.
private enum AXSelectionReader {
    static func read(processID: pid_t, bundleID: String?, fallbackAnchor: CGPoint) -> AXSelectionSample? {
        guard AXIsProcessTrusted(), processID != ProcessInfo.processInfo.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(processID)
        if let focused = attribute(application, kAXFocusedUIElementAttribute) as? AXUIElement,
           let sample = selectedText(from: focused, anchor: fallbackAnchor) {
            return sample
        }
        guard bundleID == "com.apple.finder" else { return nil }
        return selectedFiles(in: application, anchor: fallbackAnchor)
    }

    private static func selectedText(from element: AXUIElement, anchor: CGPoint) -> AXSelectionSample? {
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        if subrole == kAXSecureTextFieldSubrole as String {
            return AXSelectionSample(fingerprint: "secure", payloads: [], omittedCount: 0, anchor: nil, isSecureField: true)
        }
        guard let value = attribute(element, kAXSelectedTextAttribute) as? String,
              !value.isEmpty, value.utf8.count <= BubbleShelfRules.maximumTextBytes else { return nil }
        let fingerprint = "text:" + BubbleShelfItem.sha256(Data(value.utf8))
        return AXSelectionSample(fingerprint: fingerprint, payloads: [.text(value)], omittedCount: 0,
                                 anchor: anchor, isSecureField: false)
    }

    private static func selectedFiles(in application: AXUIElement, anchor: CGPoint) -> AXSelectionSample? {
        var queue: [(AXUIElement, Int)] = [(application, 0)]
        var cursor = 0
        var visited = 0
        var selected: [URL] = []
        var omittedCount = 0
        let deadline = Date().addingTimeInterval(0.55)
        while cursor < queue.count, visited < 32, Date() < deadline {
            let (element, depth) = queue[cursor]
            cursor += 1
            visited += 1
            if let children = attribute(element, kAXSelectedChildrenAttribute) as? [AXUIElement] {
                for (index, child) in children.enumerated() {
                    guard index < 80, Date() < deadline else {
                        omittedCount += children.count - index
                        break
                    }
                    if let url = fileURL(from: attribute(child, kAXURLAttribute)) { selected.append(url) }
                    else if let nested = attribute(child, kAXChildrenAttribute) as? [AXUIElement] {
                        if let url = nested.prefix(1).compactMap({ fileURL(from: attribute($0, kAXURLAttribute)) }).first {
                            selected.append(url)
                        } else {
                            omittedCount += 1
                        }
                    } else {
                        omittedCount += 1
                    }
                }
                if !selected.isEmpty { break }
            }
            guard depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            queue.append(contentsOf: children.prefix(16).map { ($0, depth + 1) })
        }
        var unique: [URL] = []
        var seen = Set<String>()
        for url in selected where seen.insert(url.standardizedFileURL.path).inserted { unique.append(url) }
        guard !unique.isEmpty else { return nil }
        let payloads = unique.map(BubbleCollectorPayload.file)
        let fingerprint = "files:" + unique.map(\.standardizedFileURL.path).joined(separator: "\u{1f}")
        return AXSelectionSample(fingerprint: fingerprint, payloads: payloads, omittedCount: omittedCount,
                                 anchor: anchor, isSecureField: false)
    }

    private static func fileURL(from value: Any?) -> URL? {
        if let url = value as? URL, url.isFileURL { return url }
        if let string = value as? String {
            if let url = URL(string: string), url.isFileURL { return url }
            let path = string.hasPrefix("file://") ? String(string.dropFirst("file://".count)) : string
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        AXUIElementSetMessagingTimeout(element, 0.025)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}
