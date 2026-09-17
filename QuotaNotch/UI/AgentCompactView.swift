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
    var accent: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !running || reduced)) { timeline in
            let drift = running && !reduced ? sin(timeline.date.timeIntervalSinceReferenceDate * 1.6) * 0.8 : 0
            let spread: CGFloat = kind == .completed ? 1 : kind == .waiting ? 4 : kind == .mixed ? 3 : 2.5
            ZStack {
                RoundedRectangle(cornerRadius: 2.2).strokeBorder(lineWidth: 1.1)
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .frame(width: 10, height: 12).offset(x: -spread / 2, y: -spread / 2)
                RoundedRectangle(cornerRadius: 2.2).fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 10, height: 12).opacity(0.15)
                RoundedRectangle(cornerRadius: 2.2).strokeBorder(lineWidth: 1.05)
                    .foregroundStyle(Color.primary.opacity(0.95))
                    .frame(width: 10, height: 12).offset(x: spread / 2, y: spread / 2)
                Group {
                    if running {
                        Capsule().frame(width: 4.5, height: 2)
                            .offset(x: spread / 2 + drift, y: spread / 2 - 2)
                    } else if kind == .waiting {
                        HStack(spacing: 1.5) {
                            Capsule().frame(width: 1.5, height: 4)
                            Capsule().frame(width: 1.5, height: 4)
                        }.offset(x: spread / 2, y: spread / 2 - 2)
                    } else if kind == .completed {
                        Circle().frame(width: 3.5, height: 3.5).offset(x: spread / 2, y: spread / 2 - 2)
                    } else {
                        Capsule().frame(width: 4.5, height: 2).offset(x: spread / 2, y: spread / 2 - 2)
                    }
                }.foregroundStyle(statusColor)
            }.frame(width: 18, height: 18)
        }.accessibilityHidden(true)
    }
    private var statusColor: Color {
        if let accent { return accent }
        switch kind {
        case .running: return AgentText.color(.running)
        case .waiting: return AgentText.color(.waiting)
        case .completed: return AgentText.color(.completed)
        case .other: return AgentText.color(.interrupted)
        case .mixed: return AgentText.color(running ? .running : .waiting)
        }
    }
    static func kind(_ state: AgentRunState) -> AgentAttentionKind {
        switch state { case .running: return .running; case .waiting: return .waiting
        case .completed: return .completed; default: return .other }
    }
}

/// Tiny state marks fit inside the existing camera-side gap, leaving task names their full width.
struct AgentTaskStateMark: View {
    static let size: CGFloat = 6
    let state: AgentRunState
    var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduced
    private let stroke = StrokeStyle(lineWidth: 0.85, lineCap: .round, lineJoin: .round)

    var body: some View {
        glyph
            .frame(width: Self.size, height: Self.size)
            .foregroundStyle(AgentText.color(state))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .running:
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduced || !animate)) { timeline in
                let angle = reduced || !animate ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
                Circle().trim(from: 0.12, to: 0.9).stroke(style: stroke)
                    .padding(0.5).rotationEffect(.degrees(angle))
            }
        case .waiting:
            HStack(spacing: 1.5) {
                Capsule().frame(width: 1, height: 4)
                Capsule().frame(width: 1, height: 4)
            }.frame(width: Self.size, height: Self.size)
        case .completed:
            Circle().strokeBorder(lineWidth: 0.85).padding(0.5)
                .overlay { Circle().frame(width: 1.3, height: 1.3) }
        case .failed:
            AgentBrokenLinkMark().stroke(style: stroke)
        case .interrupted:
            RoundedRectangle(cornerRadius: 0.6).frame(width: 4, height: 4)
        case .unknown:
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 0.85, lineCap: .round, dash: [1, 1.5]))
                .padding(0.5)
        }
    }
}

/// Two open link ends, with a visible break rather than an exclamation or cross.
private struct AgentBrokenLinkMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 2.6, y: 1.1))
        path.addLine(to: CGPoint(x: 1.8, y: 1.1))
        path.addQuadCurve(to: CGPoint(x: 0.6, y: 2.3), control: CGPoint(x: 0.6, y: 1.1))
        path.addQuadCurve(to: CGPoint(x: 1.8, y: 3.5), control: CGPoint(x: 0.6, y: 3.5))
        path.addLine(to: CGPoint(x: 2.2, y: 3.5))
        path.move(to: CGPoint(x: 3.8, y: 2.5))
        path.addLine(to: CGPoint(x: 4.2, y: 2.5))
        path.addQuadCurve(to: CGPoint(x: 5.4, y: 3.7), control: CGPoint(x: 5.4, y: 2.5))
        path.addQuadCurve(to: CGPoint(x: 4.2, y: 4.9), control: CGPoint(x: 5.4, y: 4.9))
        path.addLine(to: CGPoint(x: 3.4, y: 4.9))
        return path.applying(CGAffineTransform(scaleX: rect.width / 6, y: rect.height / 6))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
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
    @State private var dividerHovered = false
    private var summary: AgentAttentionSummary { store.attention }
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
                        AgentDividerChevron(amount: dividerHovered ? 1 : 0, direction: store.compactExpanded ? -1 : 1)
                            .stroke(Color.white.opacity(dividerHovered ? 0.82 : 0.42), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                            .frame(width: separator, height: min(14, height - 12))
                            .frame(width: separator, height: height).contentShape(Rectangle())
                            .auditNotchModule("divider", mode: "switchable")
                    }
                    .buttonStyle(.plain)
                    .onHover { value in withAnimation(motion) { dividerHovered = value } }
                    .help(store.compactExpanded ? AgentText.t("切换到额度", "Show quota widget") : AgentText.t("切换到任务", "Show task widget"))
                }
                taskButton
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .animation(motion, value: extra)
        .animation(motion, value: primaryWidth)
        .modifier(AgentModuleSwitchGesture(enabled: visible && sharesWing))
        .preference(key: AgentWingOffsetKey.self, value: (primaryWidth + extra - (anchorWidth ?? primaryWidth)) / 2)
    }
    private var taskButton: some View {
        Button {
            store.notchReadEnabled = true
            open()
        } label: {
            taskLabel.frame(width: taskWidth, height: height).contentShape(Rectangle())
        }.buttonStyle(.plain).help(summaryLabel).accessibilityLabel(summaryLabel)
            .accessibilityHint(AgentText.t("查看任务详情", "View task details"))
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
            NotchMinimalIcon(metrics: metrics) {
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
        AgentPaperGlyph(kind: summary.kind, running: summary.running > 0,
                        accent: AgentText.color(summary.waiting > 0 ? .waiting : summary.needsAction ? .failed : summary.running > 0 ? .running : summary.kind == .completed ? .completed : .interrupted))
    }
}

/// The secondary module is one centered state symbol, with no caption or numeric badge.
struct NotchMinimalIcon<Icon: View>: View {
    let metrics: NotchModuleMetrics
    @ViewBuilder let icon: () -> Icon
    var body: some View {
        icon().frame(width: metrics.minimalWidth, height: metrics.minimalIconSize)
    }
}

private struct AgentDividerChevron: Shape {
    var amount: CGFloat
    var direction: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amount, direction) }
        set { amount = newValue.first; direction = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let spread = 2.5 * amount * direction
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - spread, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + spread, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - spread, y: rect.maxY))
        return path
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

/// Task-only layout uses the existing widget/minimal footprint, with state marks in the camera-side gap.
struct AgentTaskOnlyWings: View {
    let centerWidth: CGFloat
    let height: CGFloat
    let open: () -> Void
    @ObservedObject private var store = AgentActivityStore.shared
    private var iconWidth: CGFloat { QuotaCompactMetrics.iconSize(height: height) }
    private var textWidth: CGFloat { iconWidth + NotchModuleMetrics(widgetWidth: iconWidth).additionalWidth }
    private var candidates: [AgentSession] { store.visible.filter { $0.state.isActive || store.isUnread($0) } }
    private var recent: [AgentSession] { AgentTaskOnlySummary.recent(candidates) }
    private var emphasis: AgentSession? { AgentTaskOnlySummary.emphasis(candidates) }
    var body: some View {
        HStack(spacing: QuotaCompactMetrics.spacing) {
            Button(action: open) {
                Group {
                    if let session = emphasis {
                        AgentPaperGlyph(kind: AgentPaperGlyph.kind(session.state), running: session.state == .running,
                                        accent: AgentText.color(session.state))
                            .scaleEffect(iconWidth / 16)
                    }
                }
                .frame(width: iconWidth, height: height).contentShape(Rectangle())
                .auditNotchModule("task")
            }.buttonStyle(.plain)
                .accessibilityLabel(AgentText.t("任务", "Tasks") + " · " + AgentText.state(emphasis?.state ?? .unknown))
                .catWing(.left, occupied: iconWidth, height: height)
            Color.clear.frame(width: centerWidth, height: height)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(recent, id: \.identity) { session in
                        Text(session.displayTitle.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: height < 28 ? 8 : 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(width: textWidth, alignment: .leading)
                            .overlay(alignment: .leading) {
                                AgentTaskStateMark(state: session.state)
                                    .offset(x: -(QuotaCompactMetrics.spacing + AgentTaskStateMark.size) / 2)
                            }
                    }
                }
                .frame(width: textWidth, height: height, alignment: .leading)
                .contentShape(Rectangle()).auditNotchModule("task-summary")
            }.buttonStyle(.plain)
                .accessibilityLabel(recent.map { $0.displayTitle + " · " + AgentText.state($0.state) }.joined(separator: "; "))
        }
        .frame(height: height)
        .preference(key: AgentWingOffsetKey.self, value: (textWidth - iconWidth) / 2)
    }
}
