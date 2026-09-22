// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine
import Foundation

enum BubbleCollectorAvailability: Equatable {
    case disabled
    case ready
    case accessibilityRequired
    case selectionUnavailable
    case captured
    case error
}

/// Retained as a source-compatible status type for the Shelf views. A holder
/// accepts ordinary drag data and never asks for Finder Automation permission.
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

/// Kept for preview fixtures and source compatibility. Production holders do
/// not create selection presentations or read another application's AX tree.
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
    // Compatibility state for older Shelf surfaces. Holder mode has no Finder
    // permission lifecycle, so it starts in the usable state.
    @Published private(set) var finderAutomationState: BubbleFinderAutomationState = .enabled
    @Published private(set) var statusMessage: String?
    @Published private(set) var presentation: BubbleCollectorPresentation?
    @Published private(set) var isExpanded = false
    @Published var holderLocation: CGPoint? {
        didSet {
            guard !syncingHolderLocation else { return }
            guard holderLocation != oldValue else { return }
            guard let holderLocation,
                  holderLocation.x.isFinite, holderLocation.y.isFinite else {
                store.holderLocation = nil
                if store.isReceiving { presentHolder() }
                return
            }
            store.holderLocation = holderLocation
            if store.isReceiving { presentHolder() }
        }
    }
    /// Monotonic success signal for the holder panel. It distinguishes a
    /// successful drop from a remove or duplicate item-list update.
    @Published private(set) var importRevision: UInt64 = 0

    private let store = BubbleShelfStore.shared
    private var panelController: BubbleCollectorFloatingPanel?
    private var expirationTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var stationaryAnchor: CGPoint?
    private var syncingHolderLocation = false
    private var presentingHolder = false

    private init() {
        _holderLocation = Published(initialValue: BubbleShelfStore.shared.holderLocation)
    }

    /// The holder is the visible receive surface. This name remains available
    /// to compact surfaces while the store keeps the persisted receive key for
    /// backward compatibility.
    var holderShown: Bool { store.isReceiving }
    var isHolderShown: Bool { store.isReceiving }

    var isPinnedToNotch: Bool {
        get { store.isPinnedToNotch }
        set { store.isPinnedToNotch = newValue }
    }

    /// Called by the panel after a drag completes. The panel remains visible
    /// and the point is persisted for the next launch.
    func moveHolder(to location: CGPoint) {
        holderLocation = location
    }

    /// One-way callback for panel layout. It persists a center returned by the
    /// panel without asking the panel to present itself again.
    func recordHolderLocationFromPanel(_ location: CGPoint) {
        guard location.x.isFinite, location.y.isFinite else { return }
        if holderLocation != location {
            syncingHolderLocation = true
            holderLocation = location
            syncingHolderLocation = false
        }
        if store.holderLocation != location {
            store.holderLocation = location
        }
    }

    /// The explicit Shelf toggle shows the holder without Accessibility or
    /// Finder Automation prompts.
    func startReceivingFromUser() {
        store.isReceiving = true
        generation &+= 1
        presentation = nil
        isExpanded = false
        availability = .ready
        finderAutomationState = .enabled
        statusMessage = "Drop supported content into the holder to add it to the shelf."
        presentHolder()
    }

    /// Restores only the persisted holder visibility. Existing shelf items and
    /// their original file references never turn the holder on by themselves.
    func synchronizePersistedMode() {
        guard store.isReceiving else {
            hideHolder()
            isExpanded = false
            availability = .disabled
            statusMessage = nil
            return
        }
        availability = .ready
        finderAutomationState = .enabled
        statusMessage = "Drop supported content into the holder to add it to the shelf."
        presentHolder()
    }

    /// Hides the holder while retaining all stored shelf content and its
    /// persisted position.
    func pauseReceiving() {
        store.isReceiving = false
        generation &+= 1
        isExpanded = false
        presentation = nil
        expirationTask?.cancel()
        expirationTask = nil
        stationaryAnchor = nil
        panelController?.hide()
        availability = .disabled
        statusMessage = nil
    }

    /// Compatibility action for the former permission button. Holder mode has
    /// no Accessibility requirement, so this only re-shows the holder.
    func requestAccessibilityFromUserAction() {
        guard store.isReceiving else { return }
        availability = .ready
        statusMessage = "Drop supported content into the holder to add it to the shelf."
        presentHolder()
    }

    /// Compatibility action for the former Finder permission button. It never
    /// requests Automation consent and leaves the holder usable.
    func requestFinderAutomationFromUserAction() {
        guard store.isReceiving else { return }
        finderAutomationState = .enabled
        availability = .ready
        statusMessage = "Finder permission is not needed. Drag files or folders into the holder."
        presentHolder()
    }

    func toggleExpanded() {
        guard store.isReceiving else { return }
        isExpanded.toggle()
        statusMessage = isExpanded ? "Shelf expanded." : "Shelf holder ready."
        presentHolder()
    }

    func setExpanded(_ expanded: Bool) {
        guard store.isReceiving else { return }
        isExpanded = expanded
        presentHolder()
    }

    /// The old panel click callback now expands the fixed holder. A selection
    /// fixture is still handled below so old preview runners remain buildable.
    func captureCurrentCandidate() {
        guard store.isReceiving else { return }
        #if SETTINGS_PREVIEW
        if case .selection(let selection) = presentation {
            captureFixtureSelection(selection)
            return
        }
        #endif
        toggleExpanded()
    }

    #if SETTINGS_PREVIEW
    /// Fixture-only motion helper. It does not query Accessibility or import
    /// from another application.
    func showPreviewForTesting(contents: [BubbleCollectorPayload], anchor: CGPoint) {
        generation &+= 1
        showCaptured(payloads: Array(contents.prefix(4)), anchor: anchor,
                     generation: generation, testFixture: true)
    }

    /// Compatibility fixture for the existing native preview runner. Production
    /// holder lifecycle never calls this method.
    func showSelectionForTesting(contents: [BubbleCollectorPayload], anchor: CGPoint) {
        generation &+= 1
        let selection = BubbleCollectorSelection(
            fingerprint: "fixture-" + UUID().uuidString,
            sourceProcessID: 42,
            payloads: Array(contents.prefix(80)),
            omittedCount: 0,
            anchor: anchor,
            observedAt: Date(),
            generation: generation
        )
        presentation = .selection(selection)
        stationaryAnchor = anchor
        statusMessage = "Selection fixture ready. Click the holder to save it."
        ensurePanelController().present(anchor: anchor)
        scheduleExpiration(for: selection.generation, after: 18)
    }

    /// Retained only so old preview code can compile; this is an injected
    /// fixture path and does not represent third-party selection support.
    func applySelectionSampleForTesting(contents: [BubbleCollectorPayload],
                                        sourceProcessID: Int32,
                                        fingerprint: String,
                                        anchor: CGPoint,
                                        allowUnchangedSelection: Bool = false) {
        _ = sourceProcessID
        _ = fingerprint
        _ = allowUnchangedSelection
        showSelectionForTesting(contents: contents, anchor: anchor)
    }

    func hidePreviewForTesting() {
        generation &+= 1
        expirationTask?.cancel()
        expirationTask = nil
        presentation = nil
        stationaryAnchor = nil
        panelController?.hide()
    }
    #endif

    func shutdown() {
        generation &+= 1
        expirationTask?.cancel()
        expirationTask = nil
        presentation = nil
        isExpanded = false
        stationaryAnchor = nil
        panelController?.hide()
        availability = .disabled
    }

    /// Imports only the explicit pasteboard supplied by the drop target. The
    /// holder remains at its current location and keeps its expanded state.
    @discardableResult
    func receiveDrop(_ pasteboard: NSPasteboard, sourceProcessID: Int32) -> Bool {
        _ = sourceProcessID
        guard store.isReceiving, pasteboardHasSupportedContent(pasteboard) else { return false }
        let result = store.importPasteboardManually(pasteboard)
        guard result.succeeded else {
            availability = .error
            statusMessage = result.message ?? "That content could not be added."
            presentHolder()
            return false
        }
        availability = .ready
        expirationTask?.cancel()
        expirationTask = nil
        presentation = nil
        importRevision &+= 1
        statusMessage = result.message ?? "Added to the shelf."
        presentHolder()
        return true
    }

    private func pasteboardHasSupportedContent(_ pasteboard: NSPasteboard) -> Bool {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        return !types.isDisjoint(with: BubbleCollectorPolicy.supportedDragTypes)
    }

    #if SETTINGS_PREVIEW
    private func captureFixtureSelection(_ selection: BubbleCollectorSelection) {
        guard selection.generation == generation,
              Date().timeIntervalSince(selection.observedAt) < 18 else {
            hidePreviewForTesting()
            return
        }
        let insertionGeneration = generation
        var aggregate = BubbleShelfImportResult()
        for payload in selection.payloads.reversed() {
            guard store.isReceiving, generation == insertionGeneration else { return }
            merge(insert(payload), into: &aggregate)
        }
        store.recordImportResult(aggregate)
        guard aggregate.succeeded else {
            availability = .error
            statusMessage = aggregate.message ?? "This fixture could not be added."
            return
        }
        statusMessage = aggregate.message ?? "Added to the shelf."
        let savedItems = Array(store.items.prefix(4)).map(BubbleCollectorPayload.stored)
        showCaptured(payloads: savedItems, anchor: selection.anchor,
                     generation: insertionGeneration)
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
    #endif

    private func presentHolder() {
        guard store.isReceiving else { return }
        guard !presentingHolder else { return }
        let persistedLocation = store.holderLocation
        if holderLocation != persistedLocation {
            syncingHolderLocation = true
            holderLocation = persistedLocation
            syncingHolderLocation = false
        }
        let anchor = persistedLocation ?? defaultHolderLocation()
        stationaryAnchor = anchor
        presentingHolder = true
        defer { presentingHolder = false }
        ensurePanelController().present(anchor: anchor)
    }

    private func hideHolder() {
        expirationTask?.cancel()
        expirationTask = nil
        presentation = nil
        stationaryAnchor = nil
        panelController?.hide()
    }

    private func defaultHolderLocation() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            return CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        }
        return CGPoint(x: 0, y: 0)
    }

    private func ensurePanelController() -> BubbleCollectorFloatingPanel {
        if let panelController { return panelController }
        let created = BubbleCollectorFloatingPanel(controller: self)
        panelController = created
        return created
    }
}
