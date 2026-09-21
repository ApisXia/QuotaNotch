// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import Combine
import CoreServices
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

/// Finder automation is deliberately opt-in in addition to Accessibility. A
/// denied request stays cached for the current receive session so selection
/// events never cause repeated Apple Events prompts.
enum BubbleFinderAutomationState: Equatable {
    case notRequested
    case enabled
    case denied
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
    @Published private(set) var finderAutomationState: BubbleFinderAutomationState = .notRequested
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
    private var finderPermissionRevision: UInt64 = 0
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
        finderAutomationState = .notRequested
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

    /// Explicitly tests Finder automation after the user asks for it. Passive
    /// selection events never call this method and therefore never trigger an
    /// Automation consent prompt.
    func requestFinderAutomationFromUserAction() {
        guard store.isReceiving else { return }
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else {
            statusMessage = "Finder is not running. Open Finder, then choose Allow Finder again."
            return
        }
        guard BubbleCollectorPolicy.shouldAttemptFinderAutomation(
            receiving: store.isReceiving,
            frontmostBundleID: nil,
            explicitRequest: true,
            permissionGranted: false
        ) else { return }

        let expectedGeneration = generation
        selectionReadRevision &+= 1
        let revision = selectionReadRevision
        finderAutomationState = .notRequested
        statusMessage = "Requesting Finder access…"
        axQueue.async { [weak self] in
            let result = FinderAppleEventReader.determinePermission(askUserIfNeeded: true)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.store.isReceiving,
                      self.generation == expectedGeneration,
                      self.selectionReadRevision == revision else { return }
                switch result {
                case .succeeded:
                    self.finderAutomationState = .enabled
                    self.availability = .ready
                    self.statusMessage = "Finder access is enabled. Select files in Finder or drag them into the bubble."
                case .failed(let message):
                    self.finderAutomationState = .denied
                    self.availability = .selectionUnavailable
                    self.statusMessage = message
                case .notAttempted:
                    self.statusMessage = "Finder selection access could not be checked."
                }
            }
        }
    }

    func captureCurrentCandidate() {
        guard store.isReceiving else { return }
        guard case .selection(let selection) = presentation else { return }
        guard selection.generation == generation,
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
        finderAutomationState = .notRequested
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
        refreshFinderAutomationPermission()
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

    /// Rehydrates Finder consent without prompting. The system permission is
    /// durable across pause/relaunch, while the in-memory state is deliberately
    /// reset so a revoked grant cannot make a passive Apple Event call.
    private func refreshFinderAutomationPermission() {
        guard store.isReceiving else { return }
        let expectedGeneration = generation
        finderPermissionRevision &+= 1
        let revision = finderPermissionRevision
        axQueue.async { [weak self] in
            let result = FinderAppleEventReader.determinePermission(askUserIfNeeded: false)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.store.isReceiving,
                      self.generation == expectedGeneration,
                      self.finderPermissionRevision == revision else { return }
                switch result {
                case .succeeded:
                    self.finderAutomationState = .enabled
                case .failed(let message):
                    self.finderAutomationState = .denied
                    self.statusMessage = message
                case .notAttempted:
                    // No consent yet (errAEEventWouldRequireUserConsent) is
                    // distinct from a denied/revoked grant; wait for the
                    // visible Allow Finder action instead of prompting.
                    break
                }
            }
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
        let finderAutomation: FinderAutomationReadMode = finderAutomationState == .enabled ? .enabled : .disabled
        axQueue.async { [weak self] in
            let result = AXSelectionReader.read(
                processID: processID, bundleID: bundleID, fallbackAnchor: anchor,
                finderAutomation: finderAutomation
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, self.store.isReceiving,
                      self.generation == expectedGeneration,
                      self.selectionReadRevision == revision,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return }
                var finderFailureMessage: String?
                switch result.finderAutomation {
                case .notAttempted:
                    break
                case .succeeded:
                    self.finderAutomationState = .enabled
                case .failed(let message):
                    self.finderAutomationState = .denied
                    finderFailureMessage = message
                }
                if baseline {
                    self.previousFingerprint = result.sample?.fingerprint
                } else {
                    self.applySelectionSample(result.sample, from: processID)
                }
                if let finderFailureMessage {
                    self.statusMessage = finderFailureMessage
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

private enum FinderAutomationReadMode {
    case disabled
    case enabled
    case explicit
}

private enum FinderAutomationReadOutcome {
    case notAttempted
    case succeeded
    case failed(String)
}

private struct AXSelectionReadResult {
    let sample: AXSelectionSample?
    let finderAutomation: FinderAutomationReadOutcome
}

private struct FinderAppleEventReadResult {
    let urls: [URL]
    let omittedCount: Int
    let failureMessage: String?

    var succeeded: Bool { failureMessage == nil }
}

/// Reads the frontmost app's current selection. Finder automation is only
/// attempted after the user explicitly enables it from the Shelf UI.
private enum AXSelectionReader {
    private static let finderBundleID = "com.apple.finder"
    private static let selectionAttributes = [
        kAXSelectedChildrenAttribute,
        kAXSelectedRowsAttribute,
        kAXSelectedColumnsAttribute,
        kAXSelectedCellsAttribute
    ]
    private static let maximumTraversalElements = 96
    private static let maximumChildElements = 24
    private static let maximumSelectionDepth = 8
    private static let traversalBudgetSeconds = 0.20

    static func read(
        processID: pid_t,
        bundleID: String?,
        fallbackAnchor: CGPoint,
        finderAutomation: FinderAutomationReadMode
    ) -> AXSelectionReadResult {
        guard AXIsProcessTrusted(), processID != ProcessInfo.processInfo.processIdentifier else {
            return AXSelectionReadResult(sample: nil, finderAutomation: .notAttempted)
        }
        let application = AXUIElementCreateApplication(processID)
        if let focused = axElement(from: attribute(application, kAXFocusedUIElementAttribute)),
           let sample = selectedText(from: focused, anchor: fallbackAnchor) {
            return AXSelectionReadResult(sample: sample, finderAutomation: .notAttempted)
        }
        guard bundleID == finderBundleID else {
            return AXSelectionReadResult(sample: nil, finderAutomation: .notAttempted)
        }

        if finderAutomation == .explicit {
            return readFinderAutomation(processID: processID, anchor: fallbackAnchor)
        }
        if let sample = selectedFiles(in: application, anchor: fallbackAnchor) {
            return AXSelectionReadResult(sample: sample, finderAutomation: .notAttempted)
        }
        guard finderAutomation == .enabled else {
            return AXSelectionReadResult(sample: nil, finderAutomation: .notAttempted)
        }
        return readFinderAutomation(processID: processID, anchor: fallbackAnchor)
    }

    private static func readFinderAutomation(processID: pid_t, anchor: CGPoint) -> AXSelectionReadResult {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else {
            return AXSelectionReadResult(sample: nil, finderAutomation: .notAttempted)
        }
        let permission = FinderAppleEventReader.determinePermission(askUserIfNeeded: false)
        guard case .succeeded = permission else {
            return AXSelectionReadResult(sample: nil, finderAutomation: permission)
        }
        let result = FinderAppleEventReader.read()
        guard result.succeeded else {
            return AXSelectionReadResult(
                sample: nil,
                finderAutomation: .failed(result.failureMessage ?? "Finder selection access failed.")
            )
        }
        let sample = sample(
            from: result.urls,
            omittedCount: result.omittedCount,
            anchor: anchor
        )
        return AXSelectionReadResult(sample: sample, finderAutomation: .succeeded)
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
        var remainingBudget = maximumTraversalElements
        var selected: [URL] = []
        var omittedCount = 0
        let deadline = Date().addingTimeInterval(traversalBudgetSeconds)

        while cursor < queue.count, remainingBudget > 0, Date() < deadline {
            let (element, depth) = queue[cursor]
            cursor += 1
            remainingBudget -= 1

            for attributeName in selectionAttributes {
                let selectedChildren = axElements(from: attribute(element, attributeName))
                guard !selectedChildren.isEmpty else { continue }
                if selectedChildren.count > BubbleShelfRules.maximumItemCount {
                    omittedCount += selectedChildren.count - BubbleShelfRules.maximumItemCount
                }
                let limited = selectedChildren.prefix(BubbleShelfRules.maximumItemCount)
                selected.append(contentsOf: fileURLs(
                    from: Array(limited), deadline: deadline,
                    remainingBudget: &remainingBudget, omittedCount: &omittedCount
                ))
                if !selected.isEmpty { break }
            }
            if !selected.isEmpty { break }

            guard depth < maximumSelectionDepth else { continue }
            let children = axElements(from: attribute(element, kAXChildrenAttribute))
            if children.count > maximumChildElements {
                omittedCount += children.count - maximumChildElements
            }
            queue.append(contentsOf: children.prefix(maximumChildElements).map { ($0, depth + 1) })
        }
        if cursor < queue.count { omittedCount += queue.count - cursor }
        return sample(from: selected, omittedCount: omittedCount, anchor: anchor)
    }

    private static func fileURLs(
        from roots: [AXUIElement],
        deadline: Date,
        remainingBudget: inout Int,
        omittedCount: inout Int
    ) -> [URL] {
        var queue = roots.map { ($0, 0) }
        var cursor = 0
        var urls: [URL] = []
        while cursor < queue.count, remainingBudget > 0, Date() < deadline {
            let (element, depth) = queue[cursor]
            cursor += 1
            remainingBudget -= 1
            if let url = fileURL(from: attribute(element, kAXURLAttribute)) {
                urls.append(url)
                continue
            }
            guard depth < maximumSelectionDepth else {
                omittedCount += 1
                continue
            }
            let children = axElements(from: attribute(element, kAXChildrenAttribute))
            guard !children.isEmpty else {
                omittedCount += 1
                continue
            }
            if children.count > maximumChildElements {
                omittedCount += children.count - maximumChildElements
            }
            queue.append(contentsOf: children.prefix(maximumChildElements).map { ($0, depth + 1) })
        }
        if cursor < queue.count { omittedCount += queue.count - cursor }
        return urls
    }

    private static func sample(from urls: [URL], omittedCount: Int, anchor: CGPoint) -> AXSelectionSample? {
        var unique: [URL] = []
        var seen = Set<String>()
        for url in urls where seen.insert(url.standardizedFileURL.path).inserted {
            unique.append(url)
            if unique.count == BubbleShelfRules.maximumItemCount { break }
        }
        guard !unique.isEmpty else { return nil }
        let payloads = unique.map(BubbleCollectorPayload.file)
        let fingerprint = "files:" + unique.map(\.standardizedFileURL.path).joined(separator: "\u{1f}")
        return AXSelectionSample(fingerprint: fingerprint, payloads: payloads, omittedCount: omittedCount,
                                 anchor: anchor, isSecureField: false)
    }

    private static func fileURL(from value: Any?) -> URL? {
        if let url = value as? URL, url.isFileURL { return url }
        if let url = value as? NSURL, url.isFileURL { return url as URL }
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

    private static func axElements(from value: Any?) -> [AXUIElement] {
        guard let array = value as? NSArray else { return [] }
        return array.compactMap { axElement(from: $0) }
    }

    private static func axElement(from value: Any?) -> AXUIElement? {
        guard let value else { return nil }
        let object = value as AnyObject
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return object as! AXUIElement
    }
}

private enum FinderAppleEventReader {
    private static let source = """
    with timeout of 3 seconds
        tell application id "com.apple.finder"
            set selectedItems to (get selection)
            set output to {}
            repeat with selectedItem in selectedItems
                try
                    set end of output to POSIX path of (selectedItem as alias)
                end try
            end repeat
            return output
        end tell
    end timeout
    """

    static func determinePermission(askUserIfNeeded: Bool) -> FinderAutomationReadOutcome {
        let bundleID = "com.apple.finder"
        var target = AEAddressDesc()
        let createStatus = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &target)
        }
        guard createStatus == noErr else {
            return .failed("Finder selection access could not be checked.")
        }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, askUserIfNeeded
        )
        if status == errAEEventWouldRequireUserConsent {
            return .notAttempted
        }
        guard status == noErr else { return .failed(failureMessage(for: status)) }
        return .succeeded
    }

    static func read() -> FinderAppleEventReadResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return FinderAppleEventReadResult(urls: [], omittedCount: 0,
                                              failureMessage: failureMessage(from: error))
        }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil {
            return FinderAppleEventReadResult(urls: [], omittedCount: 0,
                                              failureMessage: failureMessage(from: error))
        }
        let count = descriptor.numberOfItems
        guard count > 0 else {
            return FinderAppleEventReadResult(urls: [], omittedCount: 0, failureMessage: nil)
        }
        let limit = min(count, BubbleShelfRules.maximumItemCount)
        var urls: [URL] = []
        var omittedCount = max(0, count - limit)
        for index in 1...limit {
            guard let item = descriptor.atIndex(index),
                  let path = item.stringValue,
                  path.hasPrefix("/") else {
                omittedCount += 1
                continue
            }
            urls.append(URL(fileURLWithPath: path))
        }
        return FinderAppleEventReadResult(urls: urls, omittedCount: omittedCount, failureMessage: nil)
    }

    private static func failureMessage(from error: NSDictionary?) -> String {
        let errorNumber = (error?["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
        return failureMessage(for: OSStatus(errorNumber ?? 0))
    }

    private static func failureMessage(for status: OSStatus) -> String {
        if status == errAEEventNotPermitted || status == errAEEventWouldRequireUserConsent {
            return "Finder automation access is denied. Enable QuotaNotch under System Settings → Privacy & Security → Automation, then choose Allow Finder again."
        }
        return "Finder did not provide its selected items. Choose Allow Finder again or drag the file into the bubble."
    }
}
