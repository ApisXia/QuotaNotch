// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The pet's place in the opened notch: a narrow column beside the Tasks and Quota pages.
/// It shows the pet four times larger with one line that sums things up. It stays put when
/// the page changes. Tapping it opens the task that waits for you; an expanded task row
/// becomes the pet's focus.
@MainActor
struct NotchPetColumn: View {
    static let width: CGFloat = 104

    let page: NotchViews
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var activity = AgentActivityStore.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @AppStorage(QuotaPetKind.defaultsKey) private var petRaw = QuotaPetKind.defaultKind.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pin: QuotaPin? { store.activePin }
    private var provider: QuotaProvider { pin?.provider ?? store.selectedProvider }
    private var window: QuotaWindow? { pin.flatMap { store.window(for: $0) } }
    private var waitingTask: AgentSession? {
        activity.notchSessions.first { $0.state == .waiting }
    }
    /// The expanded task row, while the Tasks page shows.
    private var focused: AgentSession? {
        guard page == .activity, let id = activity.expandedTaskID else { return nil }
        return activity.visible.first { $0.identity == id }
    }

    /// Counts on the Tasks page, from the listed tasks.
    private var counts: (waiting: Int, running: Int, finished: Int) {
        let sessions = activity.enabled ? activity.visible : []
        return (sessions.filter { $0.state == .waiting }.count, sessions.filter { $0.state == .running }.count,
                activity.attention.states.filter { $0 == .completed }.count)
    }
    /// Nothing to report on the Tasks page: the pet dozes off now and then.
    private var resting: Bool {
        let c = counts
        return page == .activity && focused == nil && c.waiting == 0 && c.running == 0 && c.finished == 0
    }

    var body: some View {
        let lines = self.lines
        Button(action: openWaiting) {
            // The pet sits at a fixed spot from the top, so it doesn't move when the page or the
            // text below it changes; two lines are always reserved for the detail.
            VStack(spacing: 4) {
                Group {
                    if resting {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let dozing = Int(context.date.timeIntervalSinceReferenceDate / 4.2) % 2 == 1
                            pet(fixed: dozing ? .empty : .idle, signal: .none)
                        }
                    } else {
                        pet(fixed: focused.map { Self.mood($0.state) }, signal: focused.map { Self.signal($0.state) } ?? .none)
                    }
                }
                .frame(width: 104, height: 88)
                Group {
                    Text(lines.status)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(lines.color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                    Text(lines.detail)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .top)
                }
                .padding(.horizontal, 5)
            }
            .frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.white.opacity(0.045))
            // The pet's glow and ripples stay inside the column.
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(waitingTask == nil ? lines.status : AgentText.t("打开在等你的任务", "Open the task that needs you"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.status + " · " + lines.detail)
    }

    private func pet(fixed: QuotaPetMood?, signal: QuotaPetSignal) -> some View {
        QuotaPetView(kind: QuotaPetKind.choice(petRaw), size: .widget, provider: provider, window: window,
                     stale: pin == nil || store.isStale(provider), scale: 4,
                     tasks: QuotaPetTasks(activity.attention, enabled: activity.enabled),
                     fixedMood: fixed, fixedSignal: signal,
                     // 12pt of room on each side: half-size ripple pixels, six rings out, all
                     // drawn inside the pet's own frame.
                     rippleCell: 2, rippleReach: 12, contained: true)
    }

    private func openWaiting() {
        guard let task = waitingTask else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            if !activity.filter.contains(.waiting) { activity.selectNotchFilter(.all) }
            activity.notchReadEnabled = true
            coordinator.currentView = .activity
            activity.expandedTaskID = activity.expandedTaskID == task.identity ? nil : task.identity
        }
    }

    static func mood(_ state: AgentRunState) -> QuotaPetMood {
        switch state {
        case .waiting: return .needsYou
        case .running: return .working
        case .completed: return .celebrate
        case .failed: return .low
        case .interrupted, .unknown: return .stale
        }
    }

    static func signal(_ state: AgentRunState) -> QuotaPetSignal {
        switch state {
        case .waiting: return .waiting
        case .running: return .running
        default: return .none
        }
    }

    // MARK: Text

    private var lines: (status: String, detail: String, color: Color) {
        let t = AgentText.t
        let percent = window.map { QuotaText.percent($0.remainingPercent) }
        let left = percent.map { t("额度剩 \($0)%", "\($0)% quota left") } ?? t("额度未知", "Quota unknown")

        if page == .aiUsage {
            guard let window, let percent else {
                return (t("额度未知", "No quota"), t("连接后显示", "Connect to see"), .white)
            }
            // Window on the first line, reset time on the second.
            let reset = window.resetsAt.map { t("\(Self.clock($0)) 重置", "resets \(Self.clock($0))") } ?? t("重置时间未知", "reset unknown")
            return (t("剩 \(percent)%", "\(percent)% left"), window.localizedTitle + "\n" + reset, .white)
        }

        if let task = focused {
            switch task.state {
            case .waiting: return (t("这个在等你", "Needs you"), t("详情在右边", "Details at right"), AgentText.color(.waiting))
            case .running: return (t("正在跑", "Working"), left, AgentText.color(.running))
            case .completed: return (t("已经完成", "Finished"), left, AgentText.color(.completed))
            case .failed: return (t("出错了", "Error"), t("详情在右边", "Details at right"), AgentText.color(.failed))
            case .interrupted, .unknown: return (AgentText.state(task.state), left, .secondary)
            }
        }

        let sessions = activity.enabled ? activity.visible : []
        let (waiting, running, finished) = counts
        if waiting > 0 {
            return (t("\(waiting) 个在等你", "\(waiting) need you"), t("点我查看", "Tap to open"), AgentText.color(.waiting))
        }
        if running > 0 {
            return (t("\(running) 个正在跑", "\(running) working"), left, AgentText.color(.running))
        }
        if finished > 0 {
            return (t("全部完成", "All done"), t("刚完成 \(finished) 个", "\(finished) finished"), AgentText.color(.completed))
        }
        if !activity.enabled { return (t("监控已暂停", "Paused"), left, .secondary) }
        return (sessions.isEmpty ? t("没有任务", "No tasks") : t("都处理完了", "All clear"), left, .white)
    }

    /// A short reset time: "14:20" today or tomorrow, "Mon 09:00" further out.
    static func clock(_ date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = QuotaLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate(date.timeIntervalSince(now) < 20 * 3600 ? "HH:mm" : "EEE HH:mm")
        return formatter.string(from: date)
    }
}
