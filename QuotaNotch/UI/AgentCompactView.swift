// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct AgentWingOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A common paper silhouette; position and outline remain readable with motion disabled.
struct AgentPaperGlyph: View {
    let kind: AgentAttentionKind
    var running = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !running || reduced)) { timeline in
            let drift = running && !reduced ? sin(timeline.date.timeIntervalSinceReferenceDate * 1.6) * 0.8 : 0
            let spread: CGFloat = kind == .completed ? 1 : kind == .waiting ? 4 : kind == .mixed ? 3 : 2.5
            ZStack {
                RoundedRectangle(cornerRadius: 2.2).strokeBorder(lineWidth: 0.9)
                    .frame(width: 10, height: 12).offset(x: -spread / 2, y: -spread / 2).opacity(0.38)
                RoundedRectangle(cornerRadius: 2.2).fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 10, height: 12).opacity(0.15)
                RoundedRectangle(cornerRadius: 2.2).strokeBorder(lineWidth: 1.05)
                    .frame(width: 10, height: 12).offset(x: spread / 2 + drift, y: spread / 2)
                if kind == .other {
                    Capsule().frame(width: 4, height: 1).offset(x: 1.2, y: 2)
                }
            }.frame(width: 18, height: 18)
        }.accessibilityHidden(true)
    }
    static func kind(_ state: AgentRunState) -> AgentAttentionKind {
        switch state { case .running: return .running; case .waiting: return .waiting
        case .completed: return .completed; default: return .other }
    }
}

struct AgentCompactDock<Primary: View>: View {
    let primaryWidth: CGFloat
    let height: CGFloat
    var hasPrimary = true
    let open: () -> Void
    @ViewBuilder let primary: () -> Primary
    @ObservedObject private var store = AgentActivityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    @State private var retained = AgentAttentionSummary()
    private var summary: AgentAttentionSummary { hovering && !store.attention.isVisible ? retained : store.attention }
    private var visible: Bool { store.enabled && summary.isVisible }
    private var separator: CGFloat { hasPrimary && visible ? (hovering ? 22 : 12) : 0 }
    private var taskWidth: CGFloat { visible ? (store.compactExpanded ? 82 : 28) : 0 }
    private var extra: CGFloat { separator + taskWidth }
    private var motion: Animation? { reduced ? nil : .smooth(duration: 0.32) }
    var body: some View {
        HStack(spacing: 0) {
            if hasPrimary { primary().frame(width: primaryWidth, height: height) }
            if visible {
                if hasPrimary {
                    Button { withAnimation(motion) { store.compactExpanded.toggle() } } label: {
                        ChevronDivider(expanded: hovering, reversed: store.compactExpanded)
                            .frame(width: separator, height: height).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(store.compactExpanded ? AgentText.t("收起任务摘要", "Minimize tasks") : AgentText.t("展开任务摘要", "Expand tasks"))
                }
                taskButton
            }
        }
        .frame(height: height)
        .animation(motion, value: extra)
        .onChange(of: visible) { _, value in if !value { store.compactExpanded = false } }
        .onHover { value in
            if value { retained = store.attention }
            withAnimation(motion) { hovering = value }
            if !value && !store.showAccessory { store.compactExpanded = false }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height), visible else { return }
            withAnimation(motion) { store.compactExpanded = value.translation.width > 0 }
        })
        .background(AgentHorizontalScroll { right in
            if visible { withAnimation(motion) { store.compactExpanded = right } }
        })
        .preference(key: AgentWingOffsetKey.self, value: extra / 2)
    }
    private var taskButton: some View {
        Button { store.notchReadEnabled = true; open() } label: {
            taskLabel.frame(width: taskWidth, height: height).contentShape(Rectangle())
        }.buttonStyle(.plain).help(AgentText.t("打开任务", "Open tasks"))
    }
    @ViewBuilder private var taskLabel: some View {
        if store.compactExpanded {
            HStack(spacing: 6) {
                glyph
                VStack(alignment: .leading, spacing: 1) {
                    Text(taskTitle).font(.system(size: 11, weight: .medium))
                    Text(taskSubtitle).font(.system(size: 9)).foregroundStyle(.secondary)
                }.lineLimit(1)
            }
        } else {
            VStack(spacing: 0) {
                glyph.scaleEffect(height < 28 ? 0.66 : 0.78).frame(height: height < 28 ? 12 : 14)
                Text(summary.count > 99 ? "99+" : "\(summary.count)")
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
        }
    }
    private var taskTitle: String { AgentText.t("\(summary.count) 个任务", "\(summary.count) tasks") }
    private var taskSubtitle: String {
        if summary.waiting > 0 { return AgentText.t("\(summary.waiting) 个等待", "\(summary.waiting) waiting") }
        if summary.running > 0 { return AgentText.t("\(summary.running) 个进行中", "\(summary.running) working") }
        return AgentText.t("\(summary.unread) 个未读", "\(summary.unread) unread")
    }
    private var glyph: some View {
        AgentPaperGlyph(kind: summary.kind, running: summary.running > 0)
            .foregroundStyle(summary.needsAction ? AgentText.color(.waiting) : .primary)
    }
}

private struct ChevronDivider: View {
    let expanded: Bool
    let reversed: Bool
    var body: some View {
        ZStack {
            Capsule().frame(width: 1.1, height: 7).offset(y: -3.3)
                .rotationEffect(.degrees(expanded ? (reversed ? 34 : -34) : -5), anchor: .center)
            Capsule().frame(width: 1.1, height: 7).offset(y: 3.3)
                .rotationEffect(.degrees(expanded ? (reversed ? -34 : 34) : 5), anchor: .center)
        }.foregroundStyle(.white.opacity(expanded ? 0.85 : 0.32))
    }
}

/// A local event monitor only observes horizontal gestures inside its own window rectangle.
private struct AgentHorizontalScroll: NSViewRepresentable {
    let action: (Bool) -> Void
    func makeNSView(context: Context) -> ScrollRegion { let view = ScrollRegion(); view.action = action; return view }
    func updateNSView(_ view: ScrollRegion, context: Context) { view.action = action }
    final class ScrollRegion: NSView {
        var action: ((Bool) -> Void)?
        var monitor: Any?
        var last: TimeInterval = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.window === event.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), abs(event.scrollingDeltaX) > 4 else { return event }
                if event.timestamp - self.last > 0.45 { self.last = event.timestamp; self.action?(event.scrollingDeltaX < 0) }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

extension Notification.Name {
    static let agentOpenNotch = Notification.Name("QuotaNotch.agentOpenNotch")
}
