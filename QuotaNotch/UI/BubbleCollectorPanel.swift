// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class BubbleCollectorPanelFrameState: ObservableObject {
    @Published private(set) var geometry: BubbleHolderPanelGeometry

    init(geometry: BubbleHolderPanelGeometry) {
        self.geometry = geometry
    }

    func set(_ geometry: BubbleHolderPanelGeometry) {
        guard self.geometry != geometry else { return }
        self.geometry = geometry
    }
}

@MainActor
final class BubbleCollectorFloatingPanel {
    /// The 75pt material keeps a small host margin for its shadow. Expanded
    /// content grows the panel around the same global ball center.
    static let size = BubbleHolderLayout.collapsedSize

    private weak var controller: BubbleCollectorController?
    private var panel: BubbleCollectorPanel?
    private var host: NSHostingView<BubbleCollectorPreview>?
    private let frameState: BubbleCollectorPanelFrameState
    private var geometryObservation: AnyCancellable?
    private var localOutsideMonitor: Any?
    private var globalOutsideMonitor: Any?
    private var holderCenter = CGPoint(x: 320, y: 320)
    private var dragPointerOrigin: CGPoint?
    private var dragCenterOrigin: CGPoint?
    private var collapseTask: Task<Void, Never>?
    private var collapseGeneration: UInt64 = 0
    private var outsideMouseDownPoint: CGPoint?
    private var outsideMouseDragged = false

    init(controller: BubbleCollectorController) {
        self.controller = controller
        let initialGeometry = BubbleHolderLayout.panelGeometry(
            center: holderCenter, itemCount: 0, expanded: false,
            visibleFrames: NSScreen.screens.map(\.visibleFrame))
        self.frameState = BubbleCollectorPanelFrameState(geometry: initialGeometry)

        let panel = BubbleCollectorPanel(contentRect: initialGeometry.panelFrame,
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.identifier = NSUserInterfaceItemIdentifier("bubble-collector-preview-panel")
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel

        geometryObservation = frameState.$geometry.sink { [weak self] geometry in
            self?.apply(geometry)
        }
    }

    func present(anchor: CGPoint) {
        holderCenter = clampedHolderCenter(anchor)
        controller?.recordHolderLocationFromPanel(holderCenter)
        if controller?.isExpanded == false, frameState.geometry.expanded {
            scheduleCollapseGeometry()
        } else {
            updateGeometry()
        }
        ensureHost()
        panel?.orderFrontRegardless()
    }

    func hide() {
        collapseTask?.cancel()
        collapseTask = nil
        collapseGeneration &+= 1
        removeOutsideMonitors()
        dragPointerOrigin = nil
        dragCenterOrigin = nil
        // Hiding is an immediate lifecycle stop (pause, shutdown, or a
        // preview reset), so do not leave an expanded canvas behind for the
        // next presentation to mistake for an in-progress collapse.
        if controller?.isExpanded == false, frameState.geometry.expanded {
            updateGeometry()
        }
        panel?.orderOut(nil)
        // Detaching the hosting view stops its TimelineView/Metal work while hidden.
        panel?.contentView = nil
        host = nil
    }

    func updateForContentChange() {
        // Keep the expanded canvas alive while the reverse animation is running;
        // shrinking it here would clip the row before expansionProgress reaches 0.
        guard controller?.isExpanded == true || !frameState.geometry.expanded else { return }
        updateGeometry()
    }

    func setExpanded(_ expanded: Bool) {
        collapseTask?.cancel()
        collapseTask = nil
        collapseGeneration &+= 1
        if expanded {
            updateGeometry()
            installOutsideMonitors()
        } else {
            scheduleCollapseGeometry()
        }
    }

    private func scheduleCollapseGeometry() {
        guard frameState.geometry.expanded else {
            removeOutsideMonitors()
            return
        }
        collapseGeneration &+= 1
        let expectedGeneration = collapseGeneration
        collapseTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled, let self,
                  self.collapseGeneration == expectedGeneration,
                  self.controller?.isExpanded == false else { return }
            self.updateGeometry()
            self.removeOutsideMonitors()
            self.collapseTask = nil
        }
    }

    func beginHolderDrag(at pointer: CGPoint) {
        dragPointerOrigin = pointer
        dragCenterOrigin = holderCenter
    }

    func moveHolder(to pointer: CGPoint) {
        guard let dragPointerOrigin, let dragCenterOrigin else { return }
        let delta = CGPoint(x: pointer.x - dragPointerOrigin.x,
                            y: pointer.y - dragPointerOrigin.y)
        let next = CGPoint(x: dragCenterOrigin.x + delta.x,
                           y: dragCenterOrigin.y + delta.y)
        holderCenter = clampedHolderCenter(next)
        controller?.recordHolderLocationFromPanel(holderCenter)
        updateGeometry()
    }

    func endHolderDrag() {
        dragPointerOrigin = nil
        dragCenterOrigin = nil
    }

    private func ensureHost() {
        guard host == nil, let controller else { return }
        let root = BubbleCollectorPreview(
            controller: controller,
            frameState: frameState,
            onMoveStart: { [weak self] point in self?.beginHolderDrag(at: point) },
            onMove: { [weak self] point in self?.moveHolder(to: point) },
            onMoveEnd: { [weak self] in self?.endHolderDrag() },
            onContentChange: { [weak self] in self?.updateForContentChange() },
            onExpansionChange: { [weak self] expanded in self?.setExpanded(expanded) }
        )
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: frameState.geometry.canvasSize)
        host.autoresizingMask = [.width, .height]
        panel?.contentView = host
        self.host = host
        apply(frameState.geometry)
    }

    private func updateGeometry() {
        guard let controller else { return }
        let geometry = BubbleHolderLayout.panelGeometry(
            center: holderCenter,
            itemCount: BubbleShelfStore.shared.items.count,
            expanded: controller.isExpanded,
            visibleFrames: NSScreen.screens.map(\.visibleFrame))
        frameState.set(geometry)
        if controller.isExpanded {
            installOutsideMonitors()
        }
    }

    private func apply(_ geometry: BubbleHolderPanelGeometry) {
        guard let panel else { return }
        host?.frame = CGRect(origin: .zero, size: geometry.canvasSize)
        panel.setFrame(geometry.panelFrame, display: true)
    }

    private func clampedHolderCenter(_ point: CGPoint) -> CGPoint {
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let screen = frames.first(where: { $0.contains(point) }) ?? frames.min(by: {
            squaredDistance(from: point, to: $0) < squaredDistance(from: point, to: $1)
        }) else { return point }
        let radius = BubbleHolderLayout.ballDiameter / 2 + BubbleHolderLayout.panelMargin
        return CGPoint(x: min(max(point.x, screen.minX + radius), screen.maxX - radius),
                       y: min(max(point.y, screen.minY + radius), screen.maxY - radius))
    }

    private func installOutsideMonitors() {
        guard localOutsideMonitor == nil, globalOutsideMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            guard let self else { return event }
            self.handleOutsideEvent(event)
            return event
        }
        globalOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] event in
            self?.handleOutsideEvent(event)
        }
    }

    private func handleOutsideEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            guard isOutsideInteractiveRegion(event) else { return }
            outsideMouseDownPoint = screenPoint(for: event)
            outsideMouseDragged = false
        case .leftMouseDragged:
            guard outsideMouseDownPoint != nil else { return }
            outsideMouseDragged = true
        case .leftMouseUp:
            guard outsideMouseDownPoint != nil else { return }
            let releasedOutside = isOutsideInteractiveRegion(event)
            let wasDrag = outsideMouseDragged
            self.outsideMouseDownPoint = nil
            self.outsideMouseDragged = false
            // An outside click collapses the expanded holder. A drag is left
            // alone so a Finder/file drag can enter the holder without making
            // the row disappear before performDragOperation.
            if releasedOutside && !wasDrag {
                // This monitor remains installed during the delayed reverse
                // resize. Make the action idempotent so a second outside click
                // cannot reopen the holder while that collapse is settling.
                controller?.setExpanded(false)
            }
        default:
            break
        }
    }

    private func removeOutsideMonitors() {
        if let localOutsideMonitor {
            NSEvent.removeMonitor(localOutsideMonitor)
            self.localOutsideMonitor = nil
        }
        if let globalOutsideMonitor {
            NSEvent.removeMonitor(globalOutsideMonitor)
            self.globalOutsideMonitor = nil
        }
        outsideMouseDownPoint = nil
        outsideMouseDragged = false
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        if let eventWindow = event.window {
            return eventWindow.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }

    private func isOutsideInteractiveRegion(_ event: NSEvent?) -> Bool {
        guard let panel else { return false }
        let geometry = frameState.geometry
        let point: CGPoint
        if let event {
            point = screenPoint(for: event)
        } else {
            point = NSEvent.mouseLocation
        }
        let local = CGPoint(x: point.x - panel.frame.minX,
                            y: panel.frame.maxY - point.y)
        return !geometry.interactiveFrames.contains(where: { $0.contains(local) })
    }

    private func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    deinit {
        if let geometryObservation {
            geometryObservation.cancel()
        }
        if let localOutsideMonitor {
            NSEvent.removeMonitor(localOutsideMonitor)
        }
        if let globalOutsideMonitor {
            NSEvent.removeMonitor(globalOutsideMonitor)
        }
    }
}

private final class BubbleCollectorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct BubbleCollectorPreview: View {
    @ObservedObject var controller: BubbleCollectorController
    @ObservedObject private var store = BubbleShelfStore.shared
    @ObservedObject private var frameState: BubbleCollectorPanelFrameState

    private let fixturePayloads: [BubbleCollectorPayload]?
    private let forcedExpanded: Bool?
    private let forcedPageIndex: Int?
    private let onMoveStart: ((CGPoint) -> Void)?
    private let onMove: ((CGPoint) -> Void)?
    private let onMoveEnd: (() -> Void)?
    private let onContentChange: (() -> Void)?
    private let onExpansionChange: ((Bool) -> Void)?

    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    @State private var timelineStart = Date()
    @State private var expansionProgress: CGFloat
    @State private var pageIndex: Int
    @State private var priorContentIDs: [String] = []
    @State private var dropPulseStart: Date?

    init(controller: BubbleCollectorController,
         frameState: BubbleCollectorPanelFrameState,
         fixturePayloads: [BubbleCollectorPayload]? = nil,
         pointer: CGPoint = CGPoint(x: 0.5, y: 0.5),
         forcedExpanded: Bool? = nil,
         forcedPageIndex: Int? = nil,
         onMoveStart: ((CGPoint) -> Void)? = nil,
         onMove: ((CGPoint) -> Void)? = nil,
         onMoveEnd: (() -> Void)? = nil,
         onContentChange: (() -> Void)? = nil,
         onExpansionChange: ((Bool) -> Void)? = nil) {
        self.controller = controller
        self._frameState = ObservedObject(wrappedValue: frameState)
        self.fixturePayloads = fixturePayloads
        self.forcedExpanded = forcedExpanded
        self.forcedPageIndex = forcedPageIndex
        self.onMoveStart = onMoveStart
        self.onMove = onMove
        self.onMoveEnd = onMoveEnd
        self.onContentChange = onContentChange
        self.onExpansionChange = onExpansionChange
        self._pointer = State(initialValue: pointer)
        self._expansionProgress = State(initialValue: forcedExpanded == true ? 1 : 0)
        self._pageIndex = State(initialValue: forcedPageIndex ?? 0)
    }

    private var isExpanded: Bool { forcedExpanded ?? controller.isExpanded }

    private var displayedPayloads: [BubbleCollectorPayload] {
        if let fixturePayloads { return fixturePayloads }
        // A holder is a view of saved shelf content. Pending selection/capture
        // presentations never invent cards before the store confirms an import.
        return store.items.map(BubbleCollectorPayload.stored)
    }

    private var contentIDs: [String] {
        displayedPayloads.map(\.id)
    }

    var body: some View {
        let payloads = displayedPayloads
        let page = BubbleHolderLayout.page(for: payloads.count, index: effectivePageIndex)
        let geometry = frameState.geometry
        let expanded = isExpanded
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSince(timelineStart)
            let breathing = (0.5 + 0.5 * sin(time * 0.68)) * (payloads.isEmpty ? 1 : 1.45)
            let shell = CollectorSphereShape(time: time, breathing: breathing)
            let shader = ShaderLibrary.default.pearlFilm(
                .boundingRect,
                .float(Float(time)),
                .float2(CGPoint(x: pointer.x, y: pointer.y)),
                .float(payloads.isEmpty ? 0 : 1),
                .float(Float(breathing))
            )
            let pulse = dropPulseStart.map {
                max(0, 1 - timeline.date.timeIntervalSince($0) / 0.36)
            } ?? 0

            ZStack {
                if !payloads.isEmpty {
                    CollectorHolderCards(payloads: payloads, page: page,
                                         geometry: geometry,
                                         progress: expansionProgress,
                                         store: store,
                                         onRemove: remove,
                                         onPageShift: { delta in
                                             pageIndex = min(page.pageCount - 1,
                                                             max(0, pageIndex + delta))
                                         })
                } else if expanded || expansionProgress > 0.02 {
                    BubbleHolderEmptyState()
                        .frame(width: geometry.rowFrame?.width ?? 160,
                               height: BubbleHolderLayout.rowHeight)
                        .position(x: geometry.rowFrame?.midX ?? geometry.ballCenter.x,
                                  y: geometry.rowFrame?.midY ?? geometry.ballCenter.y)
                        .opacity(Double(expansionProgress))
                }

                shell.fill(shader)
                    .overlay { shell.stroke(.white.opacity(0.30), lineWidth: 0.4) }
                    .frame(width: BubbleHolderLayout.ballDiameter,
                           height: BubbleHolderLayout.ballDiameter)
                    .position(geometry.ballCenter)
                    .scaleEffect(1 + 0.035 * pulse)

                if expanded, let rowFrame = geometry.rowFrame, page.pageCount > 1 {
                    BubbleHolderPageControls(page: page,
                                             rowFrame: rowFrame,
                                             onPrevious: { pageIndex = max(0, pageIndex - 1) },
                                             onNext: { pageIndex = min(page.pageCount - 1, pageIndex + 1) })
                        .opacity(Double(min(1, max(0, expansionProgress))))

                    // A trackpad emits scroll-wheel events rather than a
                    // mouse drag. Scope the native monitor to the actual row
                    // bounds so the ball remains a move/click target and the
                    // Shelf's other controls keep their normal hit testing.
                    NotchHorizontalScrollBridge(allowsVerticalPassthrough: true) { towardLeft in
                        let delta = towardLeft ? 1 : -1
                        pageIndex = min(page.pageCount - 1,
                                        max(0, pageIndex + delta))
                    }
                    .frame(width: rowFrame.width, height: rowFrame.height)
                    .position(x: rowFrame.midX, y: rowFrame.midY)
                    .allowsHitTesting(false)
                }

                BubbleCollectorDropTarget(
                    controller: controller,
                    onMoveStart: onMoveStart,
                    onMove: onMove,
                    onMoveEnd: onMoveEnd,
                    onDropSuccess: {
                        pageIndex = 0
                        dropPulseStart = Date()
                    })
                    .frame(width: BubbleHolderLayout.ballDiameter,
                           height: BubbleHolderLayout.ballDiameter)
                    .position(geometry.ballCenter)
            }
            .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
            .onContinuousHover { event in
                let location: CGPoint
                switch event {
                case .active(let point):
                    location = point
                case .ended:
                    pointer = CGPoint(x: 0.5, y: 0.5)
                    return
                }
                let ballOrigin = CGPoint(x: geometry.ballCenter.x - BubbleHolderLayout.ballDiameter / 2,
                                         y: geometry.ballCenter.y - BubbleHolderLayout.ballDiameter / 2)
                pointer = CGPoint(
                    x: min(1, max(0, (location.x - ballOrigin.x) / BubbleHolderLayout.ballDiameter)),
                    y: min(1, max(0, (location.y - ballOrigin.y) / BubbleHolderLayout.ballDiameter)))
            }
        }
        .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
        .onAppear {
            expansionProgress = isExpanded ? 1 : 0
            pageIndex = forcedPageIndex ?? (isExpanded ? pageIndex : 0)
            priorContentIDs = contentIDs
            syncPreviewGeometryIfNeeded()
        }
        .onChange(of: isExpanded) { _, expanded in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                expansionProgress = expanded ? 1 : 0
            }
            onExpansionChange?(expanded)
        }
        .task(id: isExpanded) {
            guard !isExpanded, forcedPageIndex == nil else { return }
            // @State receives the target value immediately even when its
            // transaction is animated. Keep the departing page through the
            // reverse animation, then reset after the same delay as the
            // native panel shrink. SwiftUI cancels this task when the holder
            // reopens or the view disappears.
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled else { return }
            pageIndex = 0
        }
        .onChange(of: contentIDs) { oldIDs, newIDs in
            let wasRemoval = newIDs.count < oldIDs.count
            if !wasRemoval && newIDs != oldIDs {
                pageIndex = 0
            }
            pageIndex = BubbleHolderLayout.pageIndex(for: newIDs.count, index: pageIndex)
            priorContentIDs = newIDs
            onContentChange?()
        }
    }

    private var effectivePageIndex: Int {
        forcedPageIndex ?? pageIndex
    }

    private func remove(_ payload: BubbleCollectorPayload) {
        guard case .stored(let item) = payload, !item.id.uuidString.isEmpty else { return }
        store.remove(id: item.id)
    }

    private func syncPreviewGeometryIfNeeded() {
        guard onContentChange == nil else { return }
        let geometry = BubbleHolderLayout.previewGeometry(
            itemCount: displayedPayloads.count, expanded: isExpanded)
        frameState.set(geometry)
    }
}

#if SETTINGS_PREVIEW
/// Inline native material fixture used by the settings capture runner. It never
/// starts AX monitors or imports data; callers provide the desired holder content.
struct BubbleCollectorFixtureView: View {
    let payloads: [BubbleCollectorPayload]
    let pointer: CGPoint
    let expanded: Bool
    let pageIndex: Int

    private let frameState: BubbleCollectorPanelFrameState

    init(payloads: [BubbleCollectorPayload],
         pointer: CGPoint = CGPoint(x: 0.68, y: 0.34),
         expanded: Bool = false,
         pageIndex: Int = 0) {
        self.payloads = payloads
        self.pointer = pointer
        self.expanded = expanded
        self.pageIndex = pageIndex
        self.frameState = BubbleCollectorPanelFrameState(
            geometry: BubbleHolderLayout.previewGeometry(itemCount: payloads.count,
                                                         expanded: expanded))
    }

    var body: some View {
        BubbleCollectorPreview(controller: .shared, frameState: frameState,
                               fixturePayloads: payloads, pointer: pointer,
                               forcedExpanded: expanded, forcedPageIndex: pageIndex)
    }
}
#endif

private struct CollectorSphereShape: Shape {
    var time: TimeInterval
    var breathing: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let phase = time * 0.31
        let amount = 0.010 + breathing * 0.006
        var path = Path()
        for step in 0...96 {
            let angle = Double(step) / 96 * 2 * .pi
            let wave = sin(angle * 3 + phase) * amount + cos(angle * 2 - phase * 0.72) * amount * 0.48
            let radius = 1 + wave
            let point = CGPoint(x: center.x + cos(angle) * rect.width * 0.5 * radius,
                                y: center.y + sin(angle) * rect.height * 0.5 * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct CollectorHolderCards: View {
    let payloads: [BubbleCollectorPayload]
    let page: BubbleHolderPage
    let geometry: BubbleHolderPanelGeometry
    let progress: CGFloat
    @ObservedObject var store: BubbleShelfStore
    let onRemove: (BubbleCollectorPayload) -> Void
    let onPageShift: (Int) -> Void

    var body: some View {
        let sources = BubbleHolderLayout.collapsedPlacements(page: page, ballCenter: geometry.ballCenter)
        let destinations = geometry.rowFrame.map {
            BubbleHolderLayout.expandedPlacements(page: page, rowFrame: $0)
        } ?? sources
        let entries: [HolderCardEntry] = sources.indices.compactMap { slot in
            guard slot < destinations.count else { return nil }
            let payload = payload(for: slot)
            return HolderCardEntry(id: payload.id, payload: payload,
                                   source: sources[slot], destination: destinations[slot])
        }
        ZStack {
            ForEach(entries) { entry in
                let placement = BubbleHolderLayout.interpolate(entry.source, entry.destination,
                                                                progress: progress)
                CollectorHolderCardSlot(payload: entry.payload, placement: placement,
                                        progress: progress, store: store,
                                        onRemove: { onRemove(entry.payload) })
                    .position(x: placement.isPeek
                              ? placement.frame.minX + placement.visibleWidth / 2
                              : placement.frame.midX,
                              y: placement.frame.midY)
                    .zIndex(placement.depth)
            }
        }
        .frame(width: geometry.canvasSize.width, height: geometry.canvasSize.height)
        .allowsHitTesting(progress > 0.62)
        .accessibilityHidden(progress < 0.62)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: entries.map(\.id))
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) >= 20 else { return }
                    onPageShift(value.translation.width < 0 ? 1 : -1)
                })
    }

    private func payload(for slot: Int) -> BubbleCollectorPayload {
        let index: Int
        if slot < page.clearCount {
            index = page.start + slot
        } else {
            index = page.peekIndex ?? page.start + slot
        }
        return payloads[min(max(0, index), max(0, payloads.count - 1))]
    }
}

private struct HolderCardEntry: Identifiable {
    let id: String
    let payload: BubbleCollectorPayload
    let source: BubbleHolderCardPlacement
    let destination: BubbleHolderCardPlacement
}

private struct CollectorHolderCardSlot: View {
    let payload: BubbleCollectorPayload
    let placement: BubbleHolderCardPlacement
    let progress: CGFloat
    @ObservedObject var store: BubbleShelfStore
    let onRemove: () -> Void

    var body: some View {
        let size = placement.frame.size
        let card = CollectorPreviewCard(payload: payload, size: size, store: store,
                                        removable: progress > 0.72 && !placement.isPeek,
                                        onRemove: onRemove)
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(placement.rotation))
            .opacity(placement.opacity)
            .blur(radius: placement.blur)
        if placement.isPeek {
            card.frame(width: placement.visibleWidth, height: size.height, alignment: .leading)
                .clipped()
        } else {
            card
        }
    }
}

private struct BubbleHolderPageControls: View {
    let page: BubbleHolderPage
    let rowFrame: CGRect
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: BubbleHolderLayout.controlGap) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: BubbleHolderLayout.controlWidth,
                           height: BubbleHolderLayout.controlWidth)
            }
            .buttonStyle(.plain)
            .opacity(page.hasPrevious ? 0.72 : 0.16)
            .disabled(!page.hasPrevious)

            Spacer(minLength: 0)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: BubbleHolderLayout.controlWidth,
                           height: BubbleHolderLayout.controlWidth)
            }
            .buttonStyle(.plain)
            .opacity(page.hasNext ? 0.72 : 0.16)
            .disabled(!page.hasNext)
        }
        .foregroundStyle(.white.opacity(0.88))
        .frame(width: rowFrame.width, height: rowFrame.height, alignment: .center)
        .position(x: rowFrame.midX, y: rowFrame.midY)
        .allowsHitTesting(true)
    }
}

private struct BubbleHolderEmptyState: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 11, weight: .medium))
                Text(AgentText.t("暂无已保存内容", "No saved items"))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 12)
        .background(.black.opacity(0.18), in: Capsule())
    }
}

private struct CollectorPreviewCard: View {
    let payload: BubbleCollectorPayload
    let size: CGSize
    @ObservedObject var store: BubbleShelfStore
    let removable: Bool
    let onRemove: () -> Void
    @State private var storedImage: NSImage?

    private var fileURL: URL? { payload.fileURL }
    private var displayText: String? {
        switch payload {
        case .text(let text): text
        case .stored(let item) where item.kind == .text: item.text
        case .stored(let item) where item.kind == .url: item.title
        default: nil
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = storedImage {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if let text = displayText {
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(68))
                        .font(.system(size: max(4, size.width * 0.105),
                                      weight: .medium, design: .serif))
                        .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.27))
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)
                        .padding(size.width * 0.06)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(red: 0.97, green: 0.95, blue: 0.89))
                } else {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .padding(size.width * 0.10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.92, green: 0.94, blue: 0.95).opacity(0.96))
                }
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(payload.title.prefix(22))
                    .font(.system(size: max(5, size.width * 0.105), weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                    .background(.black.opacity(0.58))
            }
            if removable {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(.black.opacity(0.68), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(2)
                .contentShape(Rectangle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: max(2, size.width * 0.06), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(2, size.width * 0.06), style: .continuous)
                .strokeBorder(.white.opacity(0.76), lineWidth: max(0.4, size.width * 0.005))
        }
        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
        .task(id: payload.id) { refreshStoredImage() }
        .onReceive(store.objectWillChange) { _ in refreshStoredImage() }
    }

    private var icon: NSImage {
        if let fileURL { return NSWorkspace.shared.icon(forFile: fileURL.path) }
        if case .stored(let item) = payload, let url = item.resourceURL, url.isFileURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(forFileType: "txt")
    }

    private func refreshStoredImage() {
        if case .stored(let item) = payload {
            storedImage = store.thumbnail(for: item)
        }
    }
}

private struct BubbleCollectorDropTarget: NSViewRepresentable {
    let controller: BubbleCollectorController
    let onMoveStart: ((CGPoint) -> Void)?
    let onMove: ((CGPoint) -> Void)?
    let onMoveEnd: (() -> Void)?
    let onDropSuccess: (() -> Void)?

    func makeNSView(context: Context) -> BubbleCollectorDropView {
        let view = BubbleCollectorDropView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: BubbleCollectorDropView, context: Context) {
        update(nsView)
    }

    private func update(_ view: BubbleCollectorDropView) {
        view.isReceiving = BubbleShelfStore.shared.isReceiving
        view.onClick = { controller.toggleExpanded() }
        view.onMoveStart = onMoveStart
        view.onMove = onMove
        view.onMoveEnd = onMoveEnd
        view.onDrop = { info in
            let sourcePID = BubbleCollectorDropView.sourceProcessID(for: info)
            let success = controller.receiveDrop(info.draggingPasteboard, sourceProcessID: sourcePID)
            if success { onDropSuccess?() }
            return success
        }
    }
}

private final class BubbleCollectorDropView: NSView {
    var isReceiving = false
    var onClick: (() -> Void)?
    var onMoveStart: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onMoveEnd: (() -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?
    private var trackingClick = false
    private var sawDrag = false
    private var dragStartPointer: CGPoint?
    private var acceptedTypes = [
        NSPasteboard.PasteboardType.fileURL,
        NSPasteboard.PasteboardType.URL,
        NSPasteboard.PasteboardType.string,
        NSPasteboard.PasteboardType.png,
        NSPasteboard.PasteboardType.tiff,
        NSPasteboard.PasteboardType("public.jpeg")
    ]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(acceptedTypes)
    }

    override func mouseDown(with event: NSEvent) {
        trackingClick = isReceiving
        sawDrag = false
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        dragStartPointer = point
        onMoveStart?(point)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard trackingClick else {
            super.mouseDragged(with: event)
            return
        }
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        if let dragStartPointer,
           hypot(point.x - dragStartPointer.x, point.y - dragStartPointer.y) >= 3 {
            sawDrag = true
            onMove?(point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if trackingClick && !sawDrag { onClick?() }
        onMoveEnd?()
        trackingClick = false
        sawDrag = false
        dragStartPointer = nil
        super.mouseUp(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sawDrag = true
        return accepts(sender) ? NSDragOperation.copy : NSDragOperation()
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sawDrag = true
        return accepts(sender) ? NSDragOperation.copy : NSDragOperation()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        accepts(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sawDrag = true
        guard accepts(sender) else { return false }
        return onDrop?(sender) ?? false
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard isReceiving, sender.draggingSourceOperationMask.contains(.copy) else { return false }
        let types = Set((sender.draggingPasteboard.types ?? []).map(\.rawValue))
        return !types.isDisjoint(with: BubbleCollectorPolicy.supportedDragTypes)
    }

    static func sourceProcessID(for info: NSDraggingInfo) -> Int32 {
        let source = info.draggingSource
        let belongsToThisApp: Bool
        if let window = source as? NSWindow {
            belongsToThisApp = NSApp.windows.contains(where: { $0 === window })
        } else if let view = source as? NSView, let window = view.window {
            belongsToThisApp = NSApp.windows.contains(where: { $0 === window })
        } else {
            belongsToThisApp = false
        }
        if belongsToThisApp { return ProcessInfo.processInfo.processIdentifier }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    }
}
