// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

private struct CatPoseKey: EnvironmentKey { static let defaultValue = CatPose() }
extension EnvironmentValues {
    var notchCatPose: CatPose {
        get { self[CatPoseKey.self] }
        set { self[CatPoseKey.self] = newValue }
    }
}
struct CatWingOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}
struct CatWingSpacesKey: PreferenceKey {
    static var defaultValue: [CatSide: CatWingSpace] = [:]
    static func reduce(value: inout [CatSide: CatWingSpace], nextValue: () -> [CatSide: CatWingSpace]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// One event queue and one lease across all notch windows.
@MainActor final class NotchCatRuntime: ObservableObject {
    static let shared = NotchCatRuntime()
    @Published private(set) var suspended = false
    private var locked = false
    private var sleeping = false
    private var observers: [NSObjectProtocol] = []
    private var windows: [UUID: String] = [:]
    private var owner: UUID?
    private var queue = CatCueQueue()
    private var nextIdle = Date().addingTimeInterval(20)

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSleeping(true) }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSleeping(false) }
        })
    }
    func setLocked(_ value: Bool) { locked = value; updateSuspension() }
    private func setSleeping(_ value: Bool) { sleeping = value; updateSuspension() }
    private func updateSuspension() {
        suspended = locked || sleeping
        queue.clear(); owner = nil
        nextIdle = Date().addingTimeInterval(20)
    }
    func register(_ id: UUID, screen: String?) {
        windows[id] = screen ?? NSScreen.main?.displayUUID ?? ""
    }
    func unregister(_ id: UUID) { windows.removeValue(forKey: id); release(id) }
    func selected(_ id: UUID) -> Bool {
        guard !suspended, let screen = windows[id] else { return false }
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayUUID
        if let pointerScreen, windows.values.contains(pointerScreen) { return screen == pointerScreen }
        if let primary = NSScreen.main?.displayUUID, windows.values.contains(primary) { return screen == primary }
        return screen == windows.values.sorted().first
    }
    func acquire(_ id: UUID) -> Bool {
        guard selected(id), owner == nil || owner == id else { return false }
        owner = id; return true
    }
    func release(_ id: UUID) { if owner == id { owner = nil } }
    func enqueue(_ cue: CatCue) {
        guard !suspended, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, UserDefaults.standard.object(forKey: "notchCatEnabled") as? Bool ?? true,
              UserDefaults.standard.object(forKey: "notchCatTaskCues") as? Bool ?? true else { return }
        queue.enqueue(cue, now: Date())
    }
    func clearCues() { queue.clear() }
    func valid(_ cue: CatCue) -> Bool {
        let store = AgentActivityStore.shared
        guard store.enabled else { return false }
        return store.visible.contains { $0.identity == cue.sessionID && $0.eventID == cue.eventID && store.isUnread($0) }
    }
    func takeCue() -> CatCue? {
        let store = AgentActivityStore.shared
        let events = Set(store.enabled ? store.unread.map(\.eventID) : [])
        return queue.take(now: Date(), valid: { events.contains($0.eventID) })
    }
    func shouldInterrupt(_ current: CatCue?) -> Bool {
        queue.pending.contains { cue in
            Date().timeIntervalSince(cue.occurredAt) <= 15 && valid(cue)
                && (current == nil || (current?.action == .completed && cue.action == .attention))
        }
    }
    var idleDue: Bool { Date() >= nextIdle }
    func finished() { nextIdle = Date().addingTimeInterval(Double.random(in: 90...180)) }
}

@MainActor final class NotchCatDirector: ObservableObject {
    @Published var pose = CatPose()
    private let id = UUID()
    private var generation = 0
    private var hoverRegions: Set<String> = []
    private var hovering: Bool { !hoverRegions.isEmpty }
    private var quietUntil = Date.distantPast
    private var currentCue: CatCue?
    private var lastSide: CatSide = .right
    private var runtime: NotchCatRuntime { .shared }

    func pointer(_ inside: Bool, source: String = "shell") {
        if inside { hoverRegions.insert(source) } else { hoverRegions.remove(source) }
        if hovering {
            // Preserve geometry beneath the pointer; decoration never intercepts a click.
            if pose.active { pose.concealed = true }
        } else { quietUntil = Date().addingTimeInterval(2) }
    }
    func stop() {
        generation += 1; pose = CatPose(); currentCue = nil
        runtime.unregister(id)
    }
    func revalidateCue() {
        if let currentCue, !runtime.valid(currentCue) { pose.concealed = true }
    }
    func clearCues() {
        runtime.clearCues()
        if currentCue != nil { pose.concealed = true }
    }
    private func delay(_ seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(Int(max(0.01, seconds) * 1000)))
    }
    func run(spaces: [CatSide: CatWingSpace], screen: String?) async {
        generation += 1
        let token = generation
        pose = CatPose(); currentCue = nil; runtime.release(id)
        runtime.register(id, screen: screen)
        defer {
            if token == generation { pose = CatPose(); currentCue = nil; runtime.unregister(id) }
        }
        #if SETTINGS_PREVIEW
        return
        #else
        let backing = screen.flatMap { NSScreen.screen(withUUID: $0)?.backingScaleFactor } ?? 2
        let sides = CatSide.allCases.filter {
            guard let space = spaces[$0] else { return false }
            return space.canPeek && space.scale(body: false, backing: backing) > 0
        }
        guard !sides.isEmpty else { return }
        do {
            // Wait for initial layout and window handoff to settle.
            try await delay(1)
            while !Task.isCancelled && token == generation {
                guard !hovering, Date() >= quietUntil, runtime.selected(id) else {
                    try await delay(1); continue
                }
                guard runtime.acquire(id) else { try await delay(1); continue }
                let cue = runtime.takeCue()
                guard cue != nil || runtime.idleDue else {
                    runtime.release(id); try await delay(1); continue
                }
                let side = sides.first { $0 != lastSide } ?? sides[0]
                guard let space = spaces[side] else { runtime.release(id); continue }
                lastSide = side
                // The approved full-body sheet faces left. Front-facing cheek poses can use
                // either edge without mirroring their marking; don't invent a rightward gait.
                let full = cue == nil && side == .left && space.canShowBody
                let action = cue?.action ?? (full || Int.random(in: 0..<3) == 0 ? .rest : .curious)
                let clip = full ? CatClips.body : CatClips.head(action)
                let scale = space.scale(body: full, backing: backing)
                guard scale > 0 else { runtime.release(id); try await delay(1); continue }
                currentCue = cue
                var elapsed = 0.0
                playback: for step in clip.steps {
                    guard !Task.isCancelled, token == generation else { return }
                    if hovering || pose.concealed || !runtime.selected(id) || runtime.shouldInterrupt(cue) { break }
                    if let cue, !runtime.valid(cue) { break }
                    let startWidth = pose.reservedWidth
                    let target = step.travel * scale
                    // Explicit short layout ticks can stop exactly where the pointer arrives.
                    // No implicit spring is allowed to keep moving a button after that point.
                    let transition = !full && startWidth != target ? min(0.18, step.duration) : 0
                    if transition > 0 {
                        for tick in 1...4 {
                            guard token == generation, !Task.isCancelled else { return }
                            if hovering || pose.concealed || !runtime.selected(id) { break playback }
                            let u = Double(tick) / 4
                            let eased = u * u * (3 - 2 * u)
                            let width = (startWidth + (target - startWidth) * eased) * backing
                            pose = CatPose(side: side, action: action, elapsed: elapsed, active: true,
                                           fullBody: full, frame: step.asset, width: width.rounded() / backing, scale: scale)
                            try await delay(transition / 4)
                        }
                    } else {
                        pose = CatPose(side: side, action: action, elapsed: elapsed, active: true,
                                       fullBody: full, frame: step.asset, width: target, scale: scale)
                    }
                    try await delay(step.duration - transition)
                    elapsed += step.duration
                }
                guard token == generation, !Task.isCancelled else { return }
                // No pose ticking while hovered or while a closed-eye hold is sleeping.
                if pose.active { pose.concealed = true }
                while hovering || Date() < quietUntil {
                    try await delay(0.5)
                    guard token == generation, !Task.isCancelled else { return }
                }
                pose = CatPose(); currentCue = nil
                runtime.finished(); runtime.release(id)
                try await delay(1)
            }
        } catch { /* Cancellation belongs to the newer generation or hidden window. */ }
        #endif
    }
}

/// Actual rendered content reports occupancy; the cat's spacer is excluded from measurement.
private struct CatWingModifier: ViewModifier {
    let side: CatSide
    let occupied: CGFloat
    let height: CGFloat
    let widgetWidth: CGFloat?
    @State private var measured: CGFloat? = nil
    @Environment(\.notchCatPose) private var pose
    private var space: CatWingSpace {
        let width = measured ?? occupied
        let widget = widgetWidth ?? QuotaCompactMetrics.iconSize(height: height)
        return CatWingSpace(occupied: width, limit: widget + NotchModuleMetrics(widgetWidth: widget).additionalWidth, height: height)
    }
    func body(content: Content) -> some View {
        let selected = pose.active && pose.side == side && space.canPeek
        let width = selected ? min(space.room, pose.reservedWidth) : 0
        HStack(spacing: 0) {
            if side == .right { Color.clear.frame(width: width) }
            content.background(GeometryReader { proxy in
                Color.clear.onAppear { measured = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, value in measured = value }
            })
            if side == .left { Color.clear.frame(width: width) }
        }
        .frame(height: height)
        .overlay(alignment: side == .left ? .trailing : .leading) {
            if selected && !pose.concealed && width > 0 {
                NotchCatDrawing(pose: pose)
                    .frame(width: width, height: height)
                    .clipped().allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .preference(key: CatWingSpacesKey.self, value: [side: space])
        .preference(key: CatWingOffsetKey.self, value: (side == .left ? -width : width) / 2)
    }
}
extension View {
    func catWing(_ side: CatSide, occupied: CGFloat, height: CGFloat, widgetWidth: CGFloat? = nil) -> some View {
        modifier(CatWingModifier(side: side, occupied: occupied, height: height, widgetWidth: widgetWidth))
    }
}

/// Cache transparent bounds once. Draw original pixels, with no vector morphing or mirroring.
private enum CatImages {
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for (kind, count) in [("cheek-rub", 6), ("edge-step", 8), ("body-sequence", 8), ("tail-bridge", 4)] {
            for index in 0..<count {
                let name = "Cat-\(kind)-\(index)"
                guard let image = NSImage(named: NSImage.Name(name)),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { continue }
                var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
                for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                    if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x + 1); maxY = max(maxY, y + 1)
                    }
                } }
                guard maxX > minX, maxY > minY,
                      let cropped = cg.cropping(to: CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX-minX), height: CGFloat(maxY-minY))) else { continue }
                result[name] = NSImage(cgImage: cropped, size: NSSize(width: CGFloat(cropped.width), height: CGFloat(cropped.height)))
            }
        }
        return result
    }()
}
struct NotchCatDrawing: View {
    let pose: CatPose
    var empty = false // Kept for the existing isolated preview runner.
    var body: some View {
        if let image = CatImages.images[pose.asset], !pose.concealed {
            Image(nsImage: image).resizable().interpolation(.none)
                .frame(width: image.size.width * pose.scale, height: image.size.height * pose.scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: pose.side == .left ? .bottomLeading : .bottomTrailing)
                .padding(.bottom, 3)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }
}
struct NotchCatSettings: View {
    @AppStorage("notchCatEnabled") private var enabled = true
    @AppStorage("notchCatTaskCues") private var taskCues = true
    var body: some View {
        Section {
            Toggle(AgentText.t("刘海猫猫", "Notch cat"), isOn: $enabled)
            if enabled {
                Toggle(AgentText.t("任务提示动作", "Task reactions"), isOn: $taskCues)
            }
        } header: { Text(AgentText.t("猫猫", "Cat")) } footer: {
            Text(AgentText.t("在两侧空余处探头，轻推有余量的组件。操作刘海时会让位。", "Peeks out beside the notch and gently nudges widgets when there is room. Gives way while you use the notch."))
        }
    }
}
