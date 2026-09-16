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
    private var summary: AgentAttentionSummary { store.attention }
    private var visible: Bool { store.enabled && summary.isVisible }
    private var metrics: NotchModuleMetrics { NotchModuleMetrics(widgetWidth: widgetWidth ?? max(0, height - 12)) }
    // A task only yields space when quota actually shares this wing (all three modules present).
    private var sharesWing: Bool { hasPrimary && primaryWidth > 0 }
    private var showsTaskWidget: Bool { !sharesWing }
    private var separator: CGFloat { sharesWing && visible ? metrics.dividerWidth : 0 }
    private var taskWidth: CGFloat { visible ? (showsTaskWidget ? metrics.widgetWidth : metrics.minimalWidth) : 0 }
    private var extra: CGFloat { separator + taskWidth }
    private var motion: Animation? { reduced ? nil : .smooth(duration: 0.32) }
    var body: some View {
        HStack(spacing: 0) {
            if sharesWing { primary().frame(width: primaryWidth, height: height) }
            if visible {
                if sharesWing {
                    Color.clear.frame(width: separator, height: height)
                        .overlay { Capsule().fill(Color.white.opacity(0.38)).frame(width: 1, height: min(14, height - 12)) }
                        .auditNotchModule("divider", mode: "static")
                        .accessibilityHidden(true)
                }
                taskButton
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .animation(motion, value: extra)
        .animation(motion, value: primaryWidth)
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
        AgentPaperGlyph(kind: summary.kind, running: summary.running > 0,
                        accent: AgentText.color(summary.waiting > 0 ? .waiting : summary.needsAction ? .failed : summary.running > 0 ? .running : summary.kind == .completed ? .completed : .interrupted))
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
