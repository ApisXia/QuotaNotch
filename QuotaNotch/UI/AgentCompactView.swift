// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct AgentWingOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
                RoundedRectangle(cornerRadius: 2.2).strokeBorder(lineWidth: 1.1)
                    .frame(width: 10, height: 12).offset(x: -spread / 2, y: -spread / 2).opacity(0.78)
                RoundedRectangle(cornerRadius: 2.2).fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 10, height: 12).opacity(0.15)
                RoundedRectangle(cornerRadius: 2.2).strokeBorder(lineWidth: 1.05)
                    .frame(width: 10, height: 12).offset(x: spread / 2, y: spread / 2)
                if running {
                    Capsule().frame(width: 3.5, height: 1.1)
                        .offset(x: spread / 2 + drift, y: spread / 2)
                } else if kind == .other {
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
    var anchorWidth: CGFloat? = nil
    var widgetWidth: CGFloat? = nil
    let open: () -> Void
    @ViewBuilder let primary: () -> Primary
    @ObservedObject private var store = AgentActivityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    @State private var retained = AgentAttentionSummary()
    private var summary: AgentAttentionSummary { hovering && !store.attention.isVisible ? retained : store.attention }
    private var visible: Bool { store.enabled && summary.isVisible }
    private var metrics: NotchModuleMetrics { NotchModuleMetrics(widgetWidth: widgetWidth ?? max(0, height - 12)) }
    // A task only yields space when quota actually shares this wing (all three modules present).
    private var sharesWing: Bool { hasPrimary && primaryWidth > 0 }
    private var showsTaskWidget: Bool { !sharesWing || store.compactExpanded }
    private var separator: CGFloat { sharesWing && visible ? metrics.dividerWidth : 0 }
    private var taskWidth: CGFloat { visible ? (showsTaskWidget ? metrics.widgetWidth : metrics.minimalWidth) : 0 }
    private var extra: CGFloat { separator + taskWidth }
    private var motion: Animation? { reduced ? nil : .smooth(duration: 0.32) }
    var body: some View {
        HStack(spacing: 0) {
            if sharesWing { primary().frame(width: primaryWidth, height: height) }
            if visible {
                if sharesWing {
                    Button { withAnimation(motion) { store.compactExpanded.toggle() } } label: {
                        ChevronDivider(expanded: hovering, reversed: store.compactExpanded)
                            .frame(width: separator, height: height).contentShape(Rectangle())
                            .auditNotchModule("switcher", mode: "enabled")
                    }.buttonStyle(.plain).help(store.compactExpanded ? AgentText.t("收起任务摘要", "Minimize tasks") : AgentText.t("展开任务摘要", "Expand tasks"))
                }
                taskButton
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .animation(motion, value: extra)
        .animation(motion, value: primaryWidth)
        .onChange(of: visible) { _, value in if !value { store.compactExpanded = false } }
        .onHover { value in
            if value { retained = store.attention }
            withAnimation(motion) { hovering = value }
            if !value && !store.showAccessory { store.compactExpanded = false }
        }
        .modifier(AgentModuleSwitchGesture(enabled: visible && sharesWing))
        .preference(key: AgentWingOffsetKey.self, value: (primaryWidth + extra - (anchorWidth ?? primaryWidth)) / 2)
    }
    private var taskButton: some View {
        Button {
            if !showsTaskWidget {
                withAnimation(motion) { store.compactExpanded = true }
            } else {
                store.notchReadEnabled = true
                open()
            }
        } label: {
            taskLabel.frame(width: taskWidth, height: height).contentShape(Rectangle())
        }.buttonStyle(.plain).help(summaryLabel).accessibilityLabel(summaryLabel)
            .accessibilityHint(showsTaskWidget ? AgentText.t("查看任务详情", "View task details") : AgentText.t("切换到任务 widget", "Show task widget"))
    }
    @ViewBuilder private var taskLabel: some View {
        if showsTaskWidget {
            glyph.scaleEffect(metrics.widgetWidth / 16)
                .frame(width: metrics.widgetWidth, height: metrics.widgetWidth)
                .overlay(alignment: .bottomTrailing) {
                    Text(countLabel).font(.system(size: min(8, metrics.widgetWidth * 0.4), weight: .medium))
                        .monospacedDigit().fixedSize()
                        .padding(.horizontal, 1).background(.black, in: RoundedRectangle(cornerRadius: 2))
                }
                .auditNotchModule("task", mode: "widget")
                .transition(.opacity)
        } else {
            NotchMinimalLabel(metrics: metrics, number: countLabel) {
                // Paper outlines have intrinsic margins; normalize their visible ink to the brand mark.
                glyph.scaleEffect(metrics.minimalIconSize / 16)
                    .frame(width: metrics.minimalIconSize, height: metrics.minimalIconSize)
            }
            .auditNotchModule("task", mode: "minimal")
            .transition(.opacity)
        }
    }
    private var summaryLabel: String { "\(summary.running) " + AgentText.state(.running) + " · \(summary.waiting) " + AgentText.state(.waiting) + " · \(summary.unread) " + AgentText.t("未读", "unread") }
    private var countLabel: String { summary.count > 99 ? "99+" : "\(summary.count)" }
    private var glyph: some View {
        AgentPaperGlyph(kind: summary.kind, running: summary.running > 0)
            .foregroundStyle(summary.needsAction ? AgentText.color(.waiting) : .primary)
    }
}

/// Fixed rows keep the glyph center and numeric baseline identical across both minimal modules.
struct NotchMinimalLabel<Icon: View>: View {
    let metrics: NotchModuleMetrics
    let number: String
    @ViewBuilder let icon: () -> Icon
    var body: some View {
        VStack(spacing: metrics.minimalSpacing) {
            icon().frame(width: metrics.minimalWidth, height: metrics.minimalIconRowHeight)
            Text(number).font(.system(size: 8, weight: .medium)).monospacedDigit().fixedSize()
                .frame(width: metrics.minimalWidth, height: metrics.minimalNumberHeight)
        }
        .frame(width: metrics.minimalWidth, height: metrics.minimalContentHeight)
    }
}

struct AgentModuleSwitchGesture: ViewModifier {
    let enabled: Bool
    @ObservedObject private var store = AgentActivityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    private func select(_ expanded: Bool) {
        guard enabled else { return }
        withAnimation(reduced ? nil : .smooth(duration: 0.32)) { store.compactExpanded = expanded }
    }
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                select(value.translation.width > 0)
            }, including: enabled ? .all : .none)
            .background {
                if enabled { AgentHorizontalScroll { right in select(right) } }
            }
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
        }.foregroundStyle(.white.opacity(expanded ? 0.75 : 0.20))
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

// The isolated preview observes the modules actually rendered, independently of fixture expectations.
// The installable build has no audit preferences or state.
#if SETTINGS_PREVIEW
struct NotchModuleAuditKey: PreferenceKey {
    static var defaultValue: [String: String] = [:]
    static func reduce(value: inout [String: String], nextValue: () -> [String: String]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif
extension View {
    @ViewBuilder func auditNotchModule(_ name: String, mode: String = "widget") -> some View {
        #if SETTINGS_PREVIEW
        self.preference(key: NotchModuleAuditKey.self, value: [name: mode])
        #else
        self
        #endif
    }
}
