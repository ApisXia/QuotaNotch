// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BubbleCollectorFloatingPanel {
    /// Keep a proportional margin around the 75pt material for its scaled
    /// shadow while preserving the exact hit-target size of the bubble.
    static let size = CGSize(width: 82, height: 82)
    private weak var controller: BubbleCollectorController?
    private var panel: BubbleCollectorPanel?
    private var host: NSHostingView<BubbleCollectorPreview>?

    init(controller: BubbleCollectorController) {
        self.controller = controller
        let panel = BubbleCollectorPanel(contentRect: CGRect(origin: .zero, size: Self.size),
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
    }

    func present(anchor: CGPoint) {
        guard let panel, let controller else { return }
        if host == nil {
            let root = BubbleCollectorPreview(controller: controller)
            let host = NSHostingView(rootView: root)
            host.frame = CGRect(origin: .zero, size: Self.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            self.host = host
        }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let frame = BubbleCollectorGeometry.panelFrame(anchor: anchor, size: Self.size,
                                                       visibleFrames: visibleFrames)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        // Detaching SwiftUI stops its animated Metal timeline while the panel is hidden.
        panel?.contentView = nil
        host = nil
    }
}

private final class BubbleCollectorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct BubbleCollectorPreview: View {
    @ObservedObject var controller: BubbleCollectorController
    @ObservedObject private var store = BubbleShelfStore.shared
    private let fixturePayloads: [BubbleCollectorPayload]?
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    @State private var timelineStart = Date()

    private let diameter: CGFloat = 75

    init(controller: BubbleCollectorController, fixturePayloads: [BubbleCollectorPayload]? = nil,
         pointer: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        self.controller = controller
        self.fixturePayloads = fixturePayloads
        self._pointer = State(initialValue: pointer)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSince(timelineStart)
            let payloads = displayedPayloads
            let phase = capturePhase(at: timeline.date)
            let breathing = (0.5 + 0.5 * sin(time * 0.68)) * (payloads.isEmpty ? 1 : 1.45)
            let shell = CollectorSphereShape(time: time, breathing: breathing)
            let shader = ShaderLibrary.default.pearlFilm(
                .boundingRect,
                .float(Float(time)),
                .float2(CGPoint(x: pointer.x, y: pointer.y)),
                .float(payloads.isEmpty ? 0 : 1),
                .float(Float(breathing))
            )

            ZStack {
                Circle().fill(.ultraThinMaterial).opacity(0.18)
                CollectorPreviewCards(payloads: payloads, diameter: diameter, store: store)
                    .opacity(Double(phase.contentOpacity))
                shell.fill(shader)
                    .overlay { shell.stroke(.white.opacity(0.30), lineWidth: 0.4) }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(shell)
            .shadow(color: Color(red: 0.48, green: 0.70, blue: 0.84).opacity(0.24), radius: 6.5, y: 3)
            .scaleEffect(phase.scale)
            .opacity(Double(phase.opacity))
            .contentShape(Circle())
            .background {
                BubbleCollectorDropTarget(controller: controller)
            }
            .onTapGesture { controller.captureCurrentCandidate() }
            .onContinuousHover { event in
                switch event {
                case .active(let location):
                    pointer = CGPoint(x: location.x / diameter, y: location.y / diameter)
                case .ended:
                    pointer = CGPoint(x: 0.5, y: 0.5)
                }
            }
            .accessibilityLabel(controller.statusMessage ?? "Bubble shelf receiver")
            .accessibilityAddTraits(.isButton)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { timelineStart = Date() }
    }

    private var displayedPayloads: [BubbleCollectorPayload] {
        if let fixturePayloads { return Array(fixturePayloads.prefix(4)) }
        guard let presentation = controller.presentation else {
            return Array(store.items.prefix(4)).map(BubbleCollectorPayload.stored)
        }
        switch presentation {
        case .selection, .drag:
            // The pending selection is frozen for the click action, but is not
            // portrayed as saved until the store confirms the import.
            return Array(store.items.prefix(4)).map(BubbleCollectorPayload.stored)
        case .captured(let payloads, _, _, _):
            return payloads
        }
    }

    private func capturePhase(at date: Date) -> CollectorCapturePhase {
        guard case .captured(_, _, let startedAt, _) = controller.presentation else { return .resting }
        let frame = BubbleCollectorMotion.frame(at: max(0, date.timeIntervalSince(startedAt)))
        return CollectorCapturePhase(scale: frame.shellScale,
                                     opacity: frame.shellOpacity,
                                     contentOpacity: frame.contentOpacity)
    }
}

#if SETTINGS_PREVIEW
/// Inline native material fixture used by the settings capture runner. It never
/// starts AX monitors or imports data; callers provide the desired stored-item
/// payloads and can render counts 0…4 with a fixed cursor light.
struct BubbleCollectorFixtureView: View {
    let payloads: [BubbleCollectorPayload]
    let pointer: CGPoint

    init(payloads: [BubbleCollectorPayload], pointer: CGPoint = CGPoint(x: 0.68, y: 0.34)) {
        self.payloads = payloads
        self.pointer = pointer
    }

    var body: some View {
        BubbleCollectorPreview(controller: .shared, fixturePayloads: payloads, pointer: pointer)
    }
}
#endif

private struct CollectorCapturePhase {
    var scale: CGFloat = 1
    var opacity: CGFloat = 1
    var contentOpacity: CGFloat = 1
    static let resting = CollectorCapturePhase()
}

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

private struct CollectorPreviewCards: View {
    let payloads: [BubbleCollectorPayload]
    let diameter: CGFloat
    @ObservedObject var store: BubbleShelfStore

    var body: some View {
        ZStack {
            ForEach(Array(payloads.prefix(4).enumerated()), id: \.element.id) { entry in
                let slot = entry.offset
                let payload = entry.element
                let layout = layout(for: slot, count: min(payloads.count, 4))
                CollectorPreviewCard(payload: payload, diameter: diameter, store: store)
                    .frame(width: diameter * layout.0, height: diameter * layout.1)
                    .rotationEffect(.degrees(layout.4))
                    .opacity(layout.6)
                    .blur(radius: diameter * layout.5)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .position(x: diameter * (0.5 + layout.2), y: diameter * (0.5 + layout.3))
                    .zIndex(Double(3 - slot))
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.smooth(duration: 0.34), value: payloads.map(\.id))
    }

    private func layout(for slot: Int, count: Int) -> (width: CGFloat, height: CGFloat,
                                                       x: CGFloat, y: CGFloat, rotation: Double,
                                                       blur: CGFloat, opacity: Double, depth: Double) {
        if count <= 1 {
            return (0.43, 0.54, -0.06, 0.04, -4, 0, 0.98, 1)
        }
        if count == 2 {
            let isFront = slot == 0
            return isFront
                ? (0.34, 0.41, -0.15, -0.05, -9, 0, 0.96, 1)
                : (0.34, 0.40, 0.14, 0.05, 7, 0, 0.88, 0)
        }
        if count == 3 {
            let layouts: [(CGFloat, CGFloat, CGFloat, CGFloat, Double, Double)] = [
                (0.37, 0.46, -0.14, -0.02, -5, 0.98),
                (0.28, 0.37, 0.16, -0.09, 6, 0.91),
                (0.27, 0.34, 0.09, 0.18, 8, 0.94)
            ]
            let item = layouts[min(slot, layouts.count - 1)]
            return (item.0, item.1, item.2, item.3, item.4, 0, item.5, Double(2 - slot))
        }
        let layouts: [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
            (0.32, 0.40, -0.120, -0.045, -8),
            (0.30, 0.37, 0.130, -0.115, 4),
            (0.28, 0.35, 0.055, 0.075, 9),
            (0.26, 0.32, -0.015, 0.142, 2)
        ]
        let item = layouts[min(slot, layouts.count - 1)]
        return (item.0, item.1, item.2, item.3, item.4,
                slot == 3 ? 0.020 : 0, slot == 3 ? 0.88 : 0.97, Double(3 - slot))
    }

}

private struct CollectorPreviewCard: View {
    let payload: BubbleCollectorPayload
    let diameter: CGFloat
    @ObservedObject var store: BubbleShelfStore
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
        Group {
            if let image = storedImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let text = displayText {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(68))
                    .font(.system(size: max(3, diameter * 0.052), weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.27))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .padding(diameter * 0.025)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(red: 0.97, green: 0.95, blue: 0.89))
            } else {
                Image(nsImage: icon)
                    .resizable().scaledToFit()
                    .padding(diameter * 0.045)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.92, green: 0.94, blue: 0.95).opacity(0.96))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: max(1.5, diameter * 0.025), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(1.5, diameter * 0.025), style: .continuous)
                .strokeBorder(.white.opacity(0.76), lineWidth: 0.325)
        }
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

    func makeNSView(context: Context) -> BubbleCollectorDropView {
        let view = BubbleCollectorDropView()
        view.onClick = { controller.captureCurrentCandidate() }
        view.onDrop = { info in
            let sourcePID = BubbleCollectorDropView.sourceProcessID(for: info)
            return controller.receiveDrop(info.draggingPasteboard, sourceProcessID: sourcePID)
        }
        return view
    }

    func updateNSView(_ nsView: BubbleCollectorDropView, context: Context) {
        nsView.isReceiving = BubbleShelfStore.shared.isReceiving
        nsView.onClick = { controller.captureCurrentCandidate() }
        nsView.onDrop = { info in
            let sourcePID = BubbleCollectorDropView.sourceProcessID(for: info)
            return controller.receiveDrop(info.draggingPasteboard, sourceProcessID: sourcePID)
        }
    }
}

private final class BubbleCollectorDropView: NSView {
    var isReceiving = false
    var onClick: (() -> Void)?
    var onDrop: ((NSDraggingInfo) -> Bool)?
    private var trackingClick = false
    private var sawDrag = false
    private let accepted = [
        NSPasteboard.PasteboardType.fileURL,
        NSPasteboard.PasteboardType.URL,
        NSPasteboard.PasteboardType.string,
        NSPasteboard.PasteboardType.png,
        NSPasteboard.PasteboardType.tiff,
        NSPasteboard.PasteboardType("public.jpeg")
    ]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(accepted)
    }

    override func mouseDown(with event: NSEvent) {
        trackingClick = isReceiving
        sawDrag = false
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if trackingClick && !sawDrag { onClick?() }
        trackingClick = false
        sawDrag = false
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
