// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import UserNotifications

@MainActor final class AgentActivityStore: ObservableObject {
    static let shared = AgentActivityStore()
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var ready = false
    @Published private(set) var issue: String?
    @Published private(set) var connected = false
    @Published private(set) var truncated = false
    @Published private(set) var now = Date()
    @Published var actionMessage: String?
    @Published var notificationsAllowed = false
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "agentMonitorEnabled")
            if enabled { start() } else { polling?.cancel(); polling = nil; sessions = []; ready = false }
        }
    }
    @Published var historyWindow: AgentHistoryWindow {
        didSet { UserDefaults.standard.set(historyWindow.rawValue, forKey: "agentMonitorHistoryHours") }
    }
    @Published var notifications: Bool {
        didSet { UserDefaults.standard.set(notifications, forKey: "agentMonitorNotifications") }
    }
    @Published private var acknowledged: [String: String]
    @Published private var dismissed: [String: String]
    @Published private var retainedReadEvents: [String: String] = [:]
    @Published var compactExpanded = false
    @Published var notchReadEnabled = false
    @Published var filter: AgentFilter = .all
    @Published var expandedTaskID: String?
    @Published private var notchOrder: [String] = []
    var notchSessions: [AgentSession] {
        let ranks = Dictionary(uniqueKeysWithValues: notchOrder.enumerated().map { ($0.element, $0.offset) })
        return visible.sorted { (ranks[$0.identity] ?? Int.max) < (ranks[$1.identity] ?? Int.max) }
    }
    func retainNotchOrder() {
        let ids = visible.map(\.identity)
        notchOrder = notchOrder.filter { ids.contains($0) }
        notchOrder += ids.filter { !notchOrder.contains($0) }
    }
    func selectNotchFilter(_ value: AgentFilter) {
        filter = value; notchReadEnabled = true
        if let id = expandedTaskID, !visible.contains(where: { $0.identity == id && value.contains($0.state) }) { expandedTaskID = nil }
    }
    func toggleInlineDetails(_ session: AgentSession) {
        expandedTaskID = expandedTaskID == session.identity ? nil : session.identity
    }
    private var polling: Task<Void, Never>?
    private var repository: AgentActivityRepository
    private var claudeRepository: ClaudeActivityRepository
    private var baseline = false
    private let monitoringStartedAt = Date()
    private var lastEvents: [String: String] = [:]
    private var lastNotificationSound = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    let claudeHome: URL
    let home: URL
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuotaNotch/Activity")
    }

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "agentMonitorEnabled") as? Bool ?? true
        notifications = defaults.bool(forKey: "agentMonitorNotifications")
        historyWindow = AgentHistoryWindow(rawValue: defaults.integer(forKey: "agentMonitorHistoryHours")) ?? .defaultValue
        acknowledged = defaults.dictionary(forKey: "agentMonitorAcknowledged") as? [String: String] ?? [:]
        dismissed = defaults.dictionary(forKey: "agentMonitorDismissed") as? [String: String] ?? [:]
        lastEvents = defaults.dictionary(forKey: "agentMonitorObserved") as? [String: String] ?? [:]
        let path = defaults.string(forKey: "agentMonitorCodexHome") ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
        home = path.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        repository = AgentActivityRepository(home: home, hookDirectory: Self.support.appendingPathComponent("events"))
        claudeHome = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        claudeRepository = ClaudeActivityRepository(home: claudeHome, hooks: Self.support.appendingPathComponent("claude-events"))
        #if !SETTINGS_PREVIEW
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refresh(force: true) } }
        #endif
    }

    var visible: [AgentSession] {
        sessions.filter {
            ($0.state.isActive || dismissed[$0.identity] != $0.eventID)
                && AgentCurrentSessions.includes($0, now: now, window: historyWindow, retained: retainedReadEvents)
        }
    }
    func finishReading() { retainedReadEvents = [:] }
    var running: Int { visible.filter { $0.state == .running }.count }
    var waiting: Int { visible.filter { $0.state == .waiting }.count }
    var unread: [AgentSession] {
        visible.filter { $0.state.isUnreadEvent && acknowledged[$0.identity] != $0.eventID }
    }
    var spotlight: AgentSession? { visible.first { $0.state == .waiting } ?? unread.first ?? visible.first { $0.state == .running } }
    var attention: AgentAttentionSummary { AgentAttentionSummary.make(visible, acknowledged: acknowledged) }
    var showAccessory: Bool { enabled && attention.isVisible }
    func isUnread(_ session: AgentSession) -> Bool { session.state.isUnreadEvent && acknowledged[session.identity] != session.eventID }
    func markRead(_ session: AgentSession, keepVisible: Bool = false) {
        if keepVisible { retainedReadEvents[session.identity] = session.eventID }
        acknowledged[session.identity] = session.eventID; saveReadState()
    }
    func markAllRead() { for session in sessions { acknowledged[session.identity] = session.eventID }; saveReadState() }
    func dismissFinished() {
        for session in sessions where !session.state.isActive {
            dismissed[session.identity] = session.eventID; acknowledged[session.identity] = session.eventID
        }
        UserDefaults.standard.set(dismissed, forKey: "agentMonitorDismissed"); saveReadState()
    }
    private func saveReadState() { UserDefaults.standard.set(acknowledged, forKey: "agentMonitorAcknowledged") }

    func start() {
        #if SETTINGS_PREVIEW
        return
        #endif
        guard enabled, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }

    func refresh(force: Bool = false) async {
        guard enabled else { return }
        async let codex = repository.scan(force: force)
        async let claude = claudeRepository.scan(force: force)
        let (codexSnapshot, claudeSnapshot) = await (codex, claude)
        var snapshot = codexSnapshot
        snapshot.sessions += claudeSnapshot.sessions
        snapshot.sessions.sort {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            return $0.updatedAt > $1.updatedAt
        }
        snapshot.truncated = codexSnapshot.truncated || claudeSnapshot.truncated
        snapshot.hasSessionDirectory = snapshot.hasSessionDirectory || claudeSnapshot.hasSessionDirectory
        snapshot.issue = [codexSnapshot.issue, claudeSnapshot.issue].compactMap { $0 }.joined(separator: "\n")
        if snapshot.issue?.isEmpty == true { snapshot.issue = nil }
        guard enabled, !Task.isCancelled else { return }
        now = Date(); issue = snapshot.issue.map { message in
            switch message {
            case "Some task records could not be read. Retrying automatically.": return AgentText.t("部分任务记录暂时无法读取，正在自动重试。", message)
            case "Codex metadata is unavailable. Using local task records.": return AgentText.t("Codex 项目资料暂时不可用，正在使用本地任务记录。", message)
            default: return message
            }
        }; truncated = snapshot.truncated
        connected = snapshot.hasDatabase || snapshot.hasSessionDirectory
        sessions = AgentCurrentSessions.latest(snapshot.sessions); ready = true
        for session in sessions {
            if !baseline && lastEvents[session.identity] == nil {
                // Starting the app must not replay yesterday's completions.
                if session.state != .waiting { acknowledged[session.identity] = session.eventID }
            } else if lastEvents[session.identity] != session.eventID,
                      (lastEvents[session.identity] != nil || (session.startedAt ?? .distantPast) > monitoringStartedAt),
                      session.state.isUnreadEvent,
                      now.timeIntervalSince(session.updatedAt) < 60 {
                sendNotification(session)
            }
            lastEvents[session.identity] = session.eventID
        }
        if !baseline { saveReadState(); baseline = true }
        let ids = Set(sessions.map(\.identity))
        lastEvents = lastEvents.filter { ids.contains($0.key) }
        if UserDefaults.standard.dictionary(forKey: "agentMonitorObserved") as? [String: String] != lastEvents {
            UserDefaults.standard.set(lastEvents, forKey: "agentMonitorObserved")
        }
        // Bound persisted metadata without storing conversation text.
        if acknowledged.count > 3000 { acknowledged = acknowledged.filter { ids.contains($0.key) }; saveReadState() }
        if dismissed.count > 3000 { dismissed = dismissed.filter { ids.contains($0.key) }; UserDefaults.standard.set(dismissed, forKey: "agentMonitorDismissed") }
    }

    func requestNotifications() async {
        do {
            notificationsAllowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notifications = notificationsAllowed
            if !notificationsAllowed { actionMessage = AgentText.t("请在系统设置中允许 QuotaNotch 通知。", "Allow QuotaNotch notifications in System Settings.") }
        } catch { actionMessage = error.localizedDescription }
    }

    private func sendNotification(_ session: AgentSession) {
        guard notifications, !isMonitorVisible else { return }
        let content = UNMutableNotificationContent()
        content.title = session.projectName + " · " + AgentText.state(session.state)
        content.body = session.displayTitle
        content.threadIdentifier = session.groupID
        content.userInfo = ["quotaNotchAgentID": session.id, "quotaNotchAgentIdentity": session.identity]
        if Date().timeIntervalSince(lastNotificationSound) > 8 {
            content.sound = .default; lastNotificationSound = Date()
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "agent-" + session.eventID, content: content, trigger: nil))
    }
    var isMonitorVisible: Bool { AgentActivityWindow.shared.window?.isKeyWindow == true }

    func showDetails(_ session: AgentSession) {
        selectNotchFilter(.all)
        expandedTaskID = session.identity
        NotificationCenter.default.post(name: .agentOpenNotch, object: nil)
    }

    #if SETTINGS_PREVIEW
    func configurePreview(_ sessions: [AgentSession]) {
        self.sessions = AgentCurrentSessions.latest(sessions)
        ready = true; connected = true; baseline = true
        acknowledged = [:]; dismissed = [:]; retainedReadEvents = [:]
    }
    #endif
}

final class AgentNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AgentNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["quotaNotchAgentID"] as? String
        let identity = info["quotaNotchAgentIdentity"] as? String
        Task { @MainActor in
            if let id {
                let store = AgentActivityStore.shared
                if let session = store.sessions.first(where: { (identity != nil ? $0.identity == identity : $0.id == id) }) { store.showDetails(session) }
                else { store.selectNotchFilter(.all); NotificationCenter.default.post(name: .agentOpenNotch, object: nil) }
            }
            completionHandler()
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum AgentText {
    static var chinese: Bool { QuotaLanguage.locale.identifier.hasPrefix("zh") || (QuotaLanguage.atLaunch == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true) }
    static func t(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    static func state(_ state: AgentRunState) -> String {
        switch state {
        case .running: return t("进行中", "Working")
        case .waiting: return t("等你处理", "Needs you")
        case .completed: return t("本轮完成", "Turn finished")
        case .interrupted: return t("已中断", "Interrupted")
        case .failed: return t("出错", "Error")
        case .unknown: return t("状态待确认", "Unconfirmed")
        }
    }
    /// Only describe observed activity; tool names are never interpreted as success or progress.
    static func activity(_ session: AgentSession, now: Date) -> String {
        switch session.state {
        case .waiting:
            return session.waitingCallID == nil ? state(.waiting) : t("等待你的回答", "Waiting for your answer")
        case .failed: return state(.failed)
        case .completed: return state(.completed)
        case .interrupted: return state(.interrupted)
        case .unknown: return state(.unknown)
        case .running: break
        }
        if session.isQuiet(at: now) { return t("暂时无新活动", "No recent activity") }
        if !session.activityDetail.isEmpty {
            let verb = session.toolIsRunning ? t("当前：", "Now: ") : t("最近：", "Recent: ")
            return verb + session.activityDetail
        }
        // A completed tool call may be followed by reasoning. Label this as recent,
        // rather than suggesting an old command is still executing.
        let tool = session.tool.components(separatedBy: "__").last?.components(separatedBy: ".").last ?? ""
        let label: String
        switch tool {
        case "exec_command", "shell", "shell_command", "write_stdin", "Bash": label = t("执行命令", "command")
        case "apply_patch", "Write", "Edit": label = t("修改文件", "file edit")
        case "web", "search_query": label = t("查询资料", "web lookup")
        case "view_image": label = t("查看图片", "image review")
        case "request_user_input_async", "request_user_input": label = t("发送提问", "question")
        case "spawn_agent", "wait_agent": label = t("协作任务", "agent coordination")
        case "update_plan": label = t("更新计划", "plan update")
        case "": return t("正在处理任务", "Task in progress")
        default: label = t("工具活动", "tool activity")
        }
        return t("最近：", "Recent: ") + label
    }
    /// Optional context adds observed information; generic calls to action are not activity.
    static func context(_ session: AgentSession, now: Date) -> String? {
        if session.state == .waiting {
            return session.waitingCallID == nil ? nil : t("等待回答", "Awaiting answer")
        }
        guard session.state == .running else { return nil }
        guard session.isQuiet(at: now) || !session.tool.isEmpty || !session.activityDetail.isEmpty else { return nil }
        return activity(session, now: now)
    }
    static func detail(_ session: AgentSession, now: Date) -> String? {
        if !session.activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return session.activityDetail }
        return context(session, now: now)
    }
    static func relativeTime(_ date: Date, now: Date) -> String? {
        guard date != .distantPast else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return t("刚刚", "Just now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return t("\(minutes) 分钟前", "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 24 { return t("\(hours) 小时前", "\(hours)h ago") }
        return t("\(hours / 24) 天前", "\(hours / 24)d ago")
    }
    static func source(_ source: AgentSurface) -> String {
        switch source { case .desktop: return "Codex"; case .vscode: return "VS Code"; case .cli: return "CLI"; case .unknown: return "Codex" }
    }
    static func color(_ state: AgentRunState) -> Color {
        switch state {
        case .running: return Color(nsColor: .systemBlue)
        case .waiting: return Color(nsColor: .systemOrange)
        case .completed: return Color(nsColor: .systemGreen)
        case .failed: return Color(nsColor: .systemRed)
        case .interrupted: return Color(nsColor: .systemPurple)
        case .unknown: return .secondary
        }
    }
    static func source(_ session: AgentSession) -> String {
        let name = session.provider == .claude ? "Claude Code" : "Codex"
        let host: String
        switch session.surface {
        case .desktop: host = t("桌面", "Desktop")
        case .vscode: host = "VS Code"
        case .cli: host = "Terminal"
        case .unknown: host = t("来源待确认", "Source unconfirmed")
        }
        return name + " · " + host
    }
    static func symbol(_ state: AgentRunState) -> String { "square.on.square" }
    static func duration(_ from: Date?, now: Date) -> String {
        guard let from else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(from)))
        if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}
