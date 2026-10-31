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
    @State private var touch = QuotaPetTouch()
    @State private var reaction: QuotaPetReaction?
    @State private var reactionStart = Date.distantPast

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
        Button(action: tapPet) {
            // The pet sits at a fixed spot from the top, so it doesn't move when the page or the
            // text below it changes; two lines are always reserved for the detail.
            VStack(spacing: 4) {
                Group {
                    if let reaction {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            reacting(reaction, elapsed: context.date.timeIntervalSince(reactionStart))
                        }
                    } else {
                        ownPet
                    }
                }
                .frame(width: 104, height: 88)
                .task(id: reactionStart) {
                    // The reaction ends on its own; a newer click restarts this with its own start.
                    guard let current = reaction else { return }
                    let start = reactionStart
                    try? await Task.sleep(for: .seconds(current.duration))
                    if reactionStart == start { reaction = nil }
                }
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
        .help(waitingTask == nil ? lines.status + " · " + AgentText.t("点一下摸摸它", "Click to pet it")
                                 : AgentText.t("打开在等你的任务", "Open the task that needs you"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.status + " · " + lines.detail)
    }

    /// The pet as it shows quota and tasks, between reactions.
    private var ownPet: some View { currentPet(touch: nil) }

    @ViewBuilder private func currentPet(touch: QuotaPetTouchMoment?) -> some View {
        if resting {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let dozing = Int(context.date.timeIntervalSinceReferenceDate / 4.2) % 2 == 1
                pet(fixed: dozing ? .empty : .idle, signal: .none, touch: touch)
            }
        } else {
            pet(fixed: focused.map { Self.mood($0.state) }, signal: focused.map { Self.signal($0.state) } ?? .none, touch: touch)
        }
    }

    /// One moment of a reaction to a click (see `QuotaPetTouchPose`): the pet view draws the face,
    /// the hop, squash, spin or shake, and the small sprites around it. Hops and spins are left
    /// out with Reduce Motion.
    private func reacting(_ reaction: QuotaPetReaction, elapsed: TimeInterval) -> some View {
        currentPet(touch: QuotaPetTouchMoment(reaction: reaction, elapsed: elapsed, reduceMotion: reduceMotion))
    }

    /// A click pets it; a click while a task waits also opens that task.
    private func tapPet() {
        let now = Date()
        let dozing = resting && Int(now.timeIntervalSinceReferenceDate / 4.2) % 2 == 1
        let asleep = dozing || (window.map { $0.remainingPercent <= 0 } ?? false)
        let next = touch.tap(at: now, asleep: asleep, waiting: waitingTask != nil)
        reaction = next
        reactionStart = now
        if next == .open { openWaiting() }
    }

    private func pet(fixed: QuotaPetMood?, signal: QuotaPetSignal, touch: QuotaPetTouchMoment? = nil) -> some View {
        QuotaPetView(kind: QuotaPetKind.choice(petRaw), size: .widget, provider: provider, window: window,
                     stale: pin == nil || store.isStale(provider), scale: 4,
                     tasks: QuotaPetTasks(activity.attention, enabled: activity.enabled),
                     fixedMood: fixed, fixedSignal: signal, touch: touch,
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
        // The first line in the pet's own words; the numbers stay on the second.
        let pet = QuotaPetKind.choice(petRaw)
        let voice = { (moment: QuotaPetVoice.Moment?) -> String? in
            guard let window else { return nil }
            let remaining = window.remainingPercent
            return QuotaPetVoice.line(pet, moment ?? QuotaPetVoice.moment(remaining: remaining), remaining: remaining,
                                      chinese: AgentText.chinese)
        }

        if page == .aiUsage {
            guard let window, let percent else {
                return (t("额度未知", "No quota"), t("连接后显示", "Connect to see"), .white)
            }
            // Window on the first line, reset time on the second.
            let reset = window.resetsAt.map { t("\(Self.clock($0)) 重置", "resets \(Self.clock($0))") } ?? t("重置时间未知", "reset unknown")
            return (voice(nil) ?? t("剩 \(percent)%", "\(percent)% left"),
                    t("剩 \(percent)% · \(reset)", "\(percent)% left · \(reset)") + "\n" + window.localizedTitle, .white)
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
            let count = t("\(waiting) 个在等你", "\(waiting) need you")
            guard let line = voice(.waiting) else { return (count, t("点我查看", "Tap to open"), AgentText.color(.waiting)) }
            return (line, count + t(" · 点我查看", " · tap to open"), AgentText.color(.waiting))
        }
        if running > 0 {
            let count = t("\(running) 个正在跑", "\(running) working")
            guard let line = voice(.working) else { return (count, left, AgentText.color(.running)) }
            return (line, count + " · " + left, AgentText.color(.running))
        }
        if finished > 0 {
            return (t("全部完成", "All done"), t("刚完成 \(finished) 个", "\(finished) finished"), AgentText.color(.completed))
        }
        if !activity.enabled { return (t("监控已暂停", "Paused"), left, .secondary) }
        let quiet = sessions.isEmpty ? t("没有任务", "No tasks") : t("都处理完了", "All clear")
        guard let line = voice(nil) else { return (quiet, left, .white) }
        return (line, quiet + " · " + left, .white)
    }

    /// A short reset time: "14:20" today or tomorrow, "Mon 09:00" further out.
    static func clock(_ date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = QuotaLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate(date.timeIntervalSince(now) < 20 * 3600 ? "HH:mm" : "EEE HH:mm")
        return formatter.string(from: date)
    }
}
