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
    @Published var notifications: Bool {
        didSet { UserDefaults.standard.set(notifications, forKey: "agentMonitorNotifications") }
    }
    @Published private var acknowledged: [String: String]
    @Published private var dismissed: [String: String]
    @Published private var pinned: Set<String>
    private var polling: Task<Void, Never>?
    private var repository: AgentActivityRepository
    private var baseline = false
    private let monitoringStartedAt = Date()
    private var lastEvents: [String: String] = [:]
    private var lastNotificationSound = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    let home: URL
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuotaNotch/Activity")
    }

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "agentMonitorEnabled") as? Bool ?? true
        notifications = defaults.bool(forKey: "agentMonitorNotifications")
        acknowledged = defaults.dictionary(forKey: "agentMonitorAcknowledged") as? [String: String] ?? [:]
        dismissed = defaults.dictionary(forKey: "agentMonitorDismissed") as? [String: String] ?? [:]
        pinned = Set(defaults.stringArray(forKey: "agentMonitorPinnedProjects") ?? [])
        let path = defaults.string(forKey: "agentMonitorCodexHome") ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
        home = path.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        repository = AgentActivityRepository(home: home, hookDirectory: Self.support.appendingPathComponent("events"))
        #if !SETTINGS_PREVIEW
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refresh(force: true) } }
        #endif
    }

    var visible: [AgentSession] { sessions.filter { dismissed[$0.id] != $0.eventID || $0.state.isActive } }
    var running: Int { visible.filter { $0.state == .running }.count }
    var waiting: Int { visible.filter { $0.state == .waiting }.count }
    var unread: [AgentSession] {
        visible.filter { [.completed, .failed, .waiting].contains($0.state) && acknowledged[$0.id] != $0.eventID }
    }
    var spotlight: AgentSession? { visible.first { $0.state == .waiting } ?? unread.first ?? visible.first { $0.state == .running } }
    var showAccessory: Bool { enabled && (running > 0 || waiting > 0 || !unread.isEmpty) }
    func isUnread(_ session: AgentSession) -> Bool { unread.contains { $0.id == session.id } }
    func isPinned(_ id: String) -> Bool { pinned.contains(id) }
    func pin(_ id: String) {
        if !pinned.insert(id).inserted { pinned.remove(id) }
        UserDefaults.standard.set(Array(pinned), forKey: "agentMonitorPinnedProjects")
    }
    func markRead(_ session: AgentSession) {
        acknowledged[session.id] = session.eventID; saveReadState()
    }
    func markAllRead() { for session in sessions { acknowledged[session.id] = session.eventID }; saveReadState() }
    func dismissFinished() {
        for session in sessions where !session.state.isActive {
            dismissed[session.id] = session.eventID; acknowledged[session.id] = session.eventID
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
        let snapshot = await repository.scan(force: force)
        guard enabled, !Task.isCancelled else { return }
        now = Date(); issue = snapshot.issue.map { message in
            switch message {
            case "Some task records could not be read. Retrying automatically.": return AgentText.t("部分任务记录暂时无法读取，正在自动重试。", message)
            case "Codex metadata is unavailable. Using local task records.": return AgentText.t("Codex 项目资料暂时不可用，正在使用本地任务记录。", message)
            default: return message
            }
        }; truncated = snapshot.truncated
        connected = snapshot.hasDatabase || snapshot.hasSessionDirectory
        sessions = snapshot.sessions; ready = true
        for session in sessions {
            if !baseline {
                // Starting the app must not replay yesterday's completions.
                if session.state != .waiting { acknowledged[session.id] = session.eventID }
            } else if lastEvents[session.id] != session.eventID,
                      (lastEvents[session.id] != nil || (session.startedAt ?? .distantPast) > monitoringStartedAt),
                      [.waiting, .completed, .failed].contains(session.state),
                      now.timeIntervalSince(session.updatedAt) < 60 {
                sendNotification(session)
            }
            lastEvents[session.id] = session.eventID
        }
        if !baseline { saveReadState(); baseline = true }
        let ids = Set(sessions.map(\.id))
        lastEvents = lastEvents.filter { ids.contains($0.key) }
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
        content.userInfo = ["quotaNotchAgentID": session.id]
        if Date().timeIntervalSince(lastNotificationSound) > 8 {
            content.sound = .default; lastNotificationSound = Date()
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "agent-" + session.eventID, content: content, trigger: nil))
    }
    var isMonitorVisible: Bool { AgentActivityWindow.shared.window?.isKeyWindow == true }

    func open(_ session: AgentSession, inVSCode: Bool? = nil) {
        guard UUID(uuidString: session.id) != nil else { actionMessage = AgentText.t("无法识别此任务的链接。", "This task has no valid session link."); return }
        let vscode = inVSCode ?? (session.surface == .vscode)
        let raw = vscode ? "vscode://openai.chatgpt/local/\(session.id)" : "codex://threads/\(session.id)"
        guard let url = URL(string: raw), NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            actionMessage = AgentText.t("没有找到对应应用。可从任务菜单复制会话 ID 或打开项目文件夹。", "The app is unavailable. Use the task menu to copy its session ID or open the project folder.")
            return
        }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error { self.actionMessage = error.localizedDescription }
                else { self.markRead(session) }
            }
        }
    }

    #if SETTINGS_PREVIEW
    func configurePreview(_ sessions: [AgentSession]) {
        self.sessions = sessions.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            return $0.updatedAt > $1.updatedAt
        }
        ready = true; connected = true; baseline = true
        acknowledged = [:]; dismissed = [:]
    }
    #endif
}

final class AgentNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AgentNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["quotaNotchAgentID"] as? String
        Task { @MainActor in
            if let id {
                let store = AgentActivityStore.shared
                if let session = store.sessions.first(where: { $0.id == id }) { store.open(session) }
                else { AgentActivityWindow.shared.show() }
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
            return session.waitingCallID == nil ? t("打开任务查看请求", "Open task to review") : t("等待你的回答", "Waiting for your answer")
        case .failed: return t("打开任务查看错误", "Open task to review error")
        case .completed: return t("可查看本轮结果", "Response ready to review")
        case .interrupted: return t("本轮已停止", "This turn was stopped")
        case .unknown: return t("等待新活动确认", "Awaiting fresh activity")
        case .running: break
        }
        if session.isQuiet(at: now) { return t("暂时无新活动", "No recent activity") }
        // A completed tool call may be followed by reasoning. Label this as recent,
        // rather than suggesting an old command is still executing.
        let tool = session.tool.components(separatedBy: "__").last?.components(separatedBy: ".").last ?? ""
        let label: String
        switch tool {
        case "exec_command", "shell", "shell_command", "write_stdin": label = t("执行命令", "command")
        case "apply_patch": label = t("修改文件", "file edit")
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
    static func source(_ source: AgentSurface) -> String {
        switch source { case .desktop: return "Codex"; case .vscode: return "VS Code"; case .cli: return "CLI"; case .unknown: return "Codex" }
    }
    static func color(_ state: AgentRunState) -> Color {
        if state == .interrupted || state == .unknown { return .secondary }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch state {
            case .running: return dark ? .systemCyan : NSColor(srgbRed: 0, green: 0.38, blue: 0.58, alpha: 1)
            case .waiting: return dark ? .systemOrange : NSColor(srgbRed: 0.65, green: 0.30, blue: 0, alpha: 1)
            case .completed: return dark ? .systemGreen : NSColor(srgbRed: 0, green: 0.43, blue: 0.18, alpha: 1)
            case .failed: return dark ? .systemRed : NSColor(srgbRed: 0.76, green: 0.14, blue: 0.13, alpha: 1)
            default: return .secondaryLabelColor
            }
        })
    }
    static func symbol(_ state: AgentRunState) -> String {
        switch state { case .running: return "circle.dotted"; case .waiting: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"; case .interrupted: return "stop.circle"
        case .failed: return "exclamationmark.circle.fill"; case .unknown: return "questionmark.circle" }
    }
    static func duration(_ from: Date?, now: Date) -> String {
        guard let from else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(from)))
        if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}
