// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct AgentNotchView: View {
    @ObservedObject private var store = AgentActivityStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var tasks: [AgentSession] {
        // Keep a row being read in place if its live status leaves the current filter.
        store.notchSessions.filter { store.filter.contains($0.state) || store.expandedTaskID == $0.identity }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(AgentFilter.allCases, id: \.self) { filter in
                    Button { withAnimation(reduced ? nil : .smooth(duration: 0.24)) { store.selectNotchFilter(filter) } } label: {
                        Text(filter.title).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(store.filter == filter ? .white : .gray)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(store.filter == filter ? Color.white.opacity(0.12) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 4)
                Text(AgentText.t("\(tasks.count) 项", "\(tasks.count) tasks"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }.frame(height: 22)
            if tasks.isEmpty {
                Text(store.enabled ? AgentText.t("当前筛选下没有任务。", "No tasks match this filter.") : AgentText.t("任务监控已暂停。", "Task monitoring is paused."))
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(tasks, id: \.identity) { session in
                                VStack(spacing: 3) {
                                    AgentNotchTaskRow(session: session, now: store.now, unread: store.isUnread(session),
                                                      expanded: store.expandedTaskID == session.identity) {
                                        store.notchReadEnabled = true
                                        withAnimation(reduced ? nil : .smooth(duration: 0.24)) { store.toggleInlineDetails(session) }
                                    }
                                    if store.expandedTaskID == session.identity {
                                        AgentInlineDetails(session: session, compact: true).transition(.opacity)
                                    }
                                }.id(session.identity)
                            }
                        }.padding(.bottom, 2)
                    }
                    .onChange(of: store.expandedTaskID) { _, id in
                        if let id { withAnimation(reduced ? nil : .smooth(duration: 0.24)) { proxy.scrollTo(id, anchor: .top) } }
                    }
                    .onAppear { if let id = store.expandedTaskID { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }
        .onAppear { store.retainNotchOrder() }
        .onDisappear { store.finishReading() }
        .onChange(of: store.visible.map(\.identity)) { _, _ in store.retainNotchOrder() }
        .padding(.horizontal, 5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum AgentNotchRowMetrics {
    static let inset: CGFloat = 7
    static let iconWidth: CGFloat = 18
    static let gap: CGFloat = 8
    static let detailLabelWidth: CGFloat = 24
    static var detailGap: CGFloat { iconWidth + gap - detailLabelWidth }
}

private struct AgentNotchTaskRow: View {
    let session: AgentSession
    let now: Date
    let unread: Bool
    let expanded: Bool
    let open: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: open) {
            HStack(spacing: AgentNotchRowMetrics.gap) {
                AgentPaperGlyph(kind: AgentPaperGlyph.kind(session.state), running: session.state == .running, accent: AgentText.color(session.state))
                    .frame(width: AgentNotchRowMetrics.iconWidth)
                identity
                status
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .medium))
                    .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(.secondary).frame(width: 8)
            }
            .opacity(!session.state.isActive && !unread && !expanded && !hovering ? 0.72 : 1)
            .padding(.horizontal, AgentNotchRowMetrics.inset).frame(height: 34)
            .background(hovering ? Color.white.opacity(0.10) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .background(AgentReadReceipt(session: session, notch: true))
        .help(tooltip)
        .accessibilityLabel(accessibilitySummary)
    }
    private var tooltip: String {
        [session.projectName, session.projectRoot, session.displayTitle, AgentText.activity(session, now: now)].joined(separator: "\n")
    }
    private var accessibilitySummary: String {
        [session.projectName, session.displayTitle, AgentText.state(session.state)].joined(separator: ", ")
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            HStack(spacing: 6) {
                Text(session.projectName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.72)).lineLimit(1).truncationMode(.middle)
                Text(AgentText.source(session)).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85)).fixedSize()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var status: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(AgentText.state(session.state))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(AgentText.color(session.state))
            if let caption = session.state.isActive ? AgentText.context(session, now: now) : AgentText.relativeTime(session.updatedAt, now: now) {
                Text(caption).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(width: 112, alignment: .trailing)
    }
}

private enum AgentTaskSection: CaseIterable {
    case attention, working, recent
    var title: String {
        switch self {
        case .attention: return AgentText.t("需要处理", "Needs attention")
        case .working: return AgentText.t("正在进行", "Working")
        case .recent: return AgentText.t("最近结果", "Recent results")
        }
    }
    func contains(_ state: AgentRunState) -> Bool {
        switch self {
        case .attention: return state == .waiting || state == .failed
        case .working: return state == .running
        case .recent: return !state.isActive && state != .failed
        }
    }
}

enum AgentFilter: String, CaseIterable {
    case active, completed, other, all
    var title: String {
        switch self { case .active: return AgentText.t("进行中", "Active"); case .completed: return AgentText.t("已完成", "Finished"); case .other: return AgentText.t("其他", "Other"); case .all: return AgentText.t("全部", "All") }
    }
    func contains(_ state: AgentRunState) -> Bool {
        switch self {
        case .active: return state == .running
        case .completed: return state == .completed
        case .other: return state != .running && state != .completed
        case .all: return true
        }
    }
}

struct AgentProjectGroup: Identifiable {
    var id: String
    var name: String
    var root: String
    var count: Int
    var waiting: Int
}

struct AgentActivityView: View {
    @ObservedObject var store: AgentActivityStore = .shared
    @State private var selectedProject = "all"
    @State private var query = ""
    private var groups: [AgentProjectGroup] {
        let grouped = Dictionary(grouping: store.visible, by: \.groupID)
        var result: [AgentProjectGroup] = []
        for (id, sessions) in grouped {
            result.append(AgentProjectGroup(id: id, name: sessions.first?.projectName ?? "Codex",
                root: sessions.first?.projectRoot ?? "", count: sessions.count, waiting: sessions.filter { $0.state == .waiting }.count))
        }
        return result.sorted {
            if ($0.waiting > 0) != ($1.waiting > 0) { return $0.waiting > 0 }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var projectSessions: [AgentSession] {
        store.visible.filter { selectedProject == "all" || $0.groupID == selectedProject }
    }
    private var filtered: [AgentSession] {
        projectSessions.filter { session in
            store.filter.contains(session.state)
            && (query.isEmpty || [session.displayTitle, session.projectName, session.cwd, session.projectRoot].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(AgentText.t("项目", "PROJECTS")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 3) {
                        projectButton(id: "all", name: AgentText.t("全部项目", "All projects"), root: "", count: store.visible.count, waiting: 0)
                        ForEach(groups, id: \.id) { group in
                            projectButton(id: group.id, name: group.name, root: group.root, count: group.count, waiting: group.waiting)
                                .contextMenu {
                                    Button(AgentText.t("复制根目录", "Copy root folder")) { copy(group.root) }
                                }
                        }
                    }.padding(.horizontal, 8)
                }
                HStack(spacing: 6) {
                    Circle().fill(store.enabled && store.connected ? .green : .secondary).frame(width: 6, height: 6)
                    Text(store.enabled ? (store.connected ? AgentText.t("本机监控", "Local monitoring") : AgentText.t("等待连接", "Waiting for activity")) : AgentText.t("已暂停", "Paused"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16)
            }.frame(width: 205).background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if let issue = store.issue {
                    Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(12)
                }
                if !store.enabled || filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(AgentTaskSection.allCases, id: \.self) { section in
                                let tasks = filtered.filter { section.contains($0.state) }
                                if !tasks.isEmpty {
                                    HStack {
                                        Text(section.title)
                                        Text("\(tasks.count)").monospacedDigit().foregroundStyle(.secondary)
                                        Spacer()
                                    }.font(.system(size: 11, weight: .semibold)).padding(.top, 14).padding(.bottom, 4)
                                    ForEach(tasks, id: \.identity) { session in
                                        AgentTaskRow(session: session, store: store)
                                        Divider().padding(.leading, 38)
                                    }
                                }
                            }
                        }.padding(.horizontal, 18).padding(.vertical, 6)
                    }
                }
                Divider()
                HStack {
                    Text(AgentText.t("项目名称自动跟随 Codex；无归属时使用根目录。", "Project names follow Codex; unassigned tasks use their root folder."))
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button { Task { await store.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help(AgentText.t("刷新", "Refresh"))
                }.padding(12)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: groups.map(\.id)) { _, ids in if selectedProject != "all" && !ids.contains(selectedProject) { selectedProject = "all" } }
        .alert(AgentText.t("任务监控", "Task monitor"), isPresented: Binding(get: { store.actionMessage != nil }, set: { if !$0 { store.actionMessage = nil } })) {
            Button(AgentText.t("好", "OK")) { store.actionMessage = nil }
        } message: { Text(store.actionMessage ?? "") }
        .task { store.start() }
        .onDisappear { store.finishReading() }
    }

    private var projectSummary: String {
        let working = projectSessions.filter { $0.state == .running }.count
        let waiting = projectSessions.filter { $0.state == .waiting }.count
        let unread = projectSessions.filter { store.isUnread($0) }.count
        return ["\(working) " + AgentText.state(.running), "\(waiting) " + AgentText.state(.waiting),
                "\(unread) " + AgentText.t("未读", "unread")].joined(separator: "   ·   ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedProject == "all" ? AgentText.t("AI 任务", "AI tasks") : (groups.first { $0.id == selectedProject }?.name ?? "Codex"))
                        .font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    Text(projectSummary)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(AgentText.t("全部标为已读", "Mark all as read")) { store.markAllRead() }
                    Button(AgentText.t("清除已结束的任务", "Clear finished tasks")) { store.dismissFinished() }
                    Divider()
                    Button(AgentText.t("监控设置", "Monitor settings")) {
                        UserDefaults.standard.set("Activity", forKey: "settingsSelectedTab")
                        SettingsWindowController.shared.showWindow()
                    }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
            }
            HStack(spacing: 12) {
                Picker("", selection: $store.filter) { ForEach(AgentFilter.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 285)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(AgentText.t("搜索任务或项目", "Search tasks or projects"), text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }.font(.system(size: 12)).padding(7).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(20)
    }

    private func projectButton(id: String, name: String, root: String, count: Int, waiting: Int) -> some View {
        Button { selectedProject = id } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: id == "all" ? "square.stack.3d.up" : "folder")
                    .font(.system(size: 12)).foregroundStyle(waiting > 0 ? AgentText.color(.waiting) : .secondary).frame(width: 15).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 12, weight: selectedProject == id ? .semibold : .regular)).lineLimit(2)
                    if groups.filter({ $0.name == name }).count > 1 && !root.isEmpty {
                        Text(root.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 1)
                Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedProject == id ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(root.isEmpty ? name : name + "\n" + root)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.enabled ? "square.stack.3d.up" : "pause.circle").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(!store.enabled ? AgentText.t("任务监控已暂停", "Monitoring is paused") : (!store.ready ? AgentText.t("正在读取任务…", "Reading tasks…") : AgentText.t("这里暂时没有任务", "No tasks here yet")))
                .font(.headline)
            Text(!store.connected ? AgentText.t("打开本机 Codex 或 Claude Code 开始工作。", "Start work in local Codex or Claude Code.") : AgentText.t("可以切换筛选，或开始一个新任务。", "Try another filter or start a new task."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !store.enabled { Button(AgentText.t("开启监控", "Enable monitoring")) { store.enabled = true } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}

struct AgentTaskRow: View {
    let session: AgentSession
    @ObservedObject var store: AgentActivityStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 10) {
            AgentPaperGlyph(kind: AgentPaperGlyph.kind(session.state), running: session.state == .running, accent: AgentText.color(session.state))
                .frame(width: 20).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(session.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if store.isUnread(session) { Circle().fill(.secondary).frame(width: 5, height: 5) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(session.projectName).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    Text(AgentText.source(session)).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).fixedSize()
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                if let context = AgentText.context(session, now: store.now) {
                    Text(context).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            VStack(alignment: .trailing, spacing: 7) {
                Text(AgentText.state(session.state)).font(.system(size: 11, weight: .medium)).foregroundStyle(AgentText.color(session.state))
                Text(session.state.isActive ? AgentText.duration(session.startedAt, now: store.now) : (AgentText.relativeTime(session.updatedAt, now: store.now) ?? ""))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }.frame(width: 94, alignment: .trailing)
            Menu {
                Button(AgentText.t("标为已读", "Mark as read")) { store.markRead(session) }
                Divider()
                Button(AgentText.t("任务详情", "Task details")) { store.toggleInlineDetails(session) }
                Button(AgentText.t("复制根目录", "Copy root folder")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.projectRoot, forType: .string) }
                Button(AgentText.t("复制会话 ID", "Copy session ID")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.id, forType: .string) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18).padding(.top, 2)
        }
        .opacity(!session.state.isActive && !store.isUnread(session) && store.expandedTaskID != session.identity ? 0.72 : 1)
        .padding(.vertical, 14).contentShape(Rectangle())
        .background(AgentReadReceipt(session: session))
        .onTapGesture { store.toggleInlineDetails(session) }
        .help(session.projectName + "\n" + session.projectRoot + "\n" + session.displayTitle)
        if store.expandedTaskID == session.identity { AgentInlineDetails(session: session).padding(.bottom, 10) }
        }
    }
}

@MainActor final class AgentActivityWindow: NSWindowController, NSWindowDelegate {
    static let shared = AgentActivityWindow()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = AgentText.t("QuotaNotch Future · 任务监控", "QuotaNotch Future · Task monitor")
        window.contentView = NSHostingView(rootView: AgentActivityView())
        window.contentMinSize = NSSize(width: 760, height: 460)
        window.setFrameAutosaveName("QuotaNotchActivityWindow")
        window.isReleasedWhenClosed = false; window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        NSApp.setActivationPolicy(.regular)
        if UserDefaults.standard.string(forKey: "NSWindow Frame QuotaNotchActivityWindow") == nil { window?.center() }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        if SettingsWindowController.shared.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }
}
