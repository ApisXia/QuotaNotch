// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct AgentActivitySettings: View {
    @ObservedObject private var store = AgentActivityStore.shared
    @State private var provider: AgentProvider = .codex
    private var configHome: URL { provider == .codex ? store.home : store.claudeHome }
    private var configFile: String { provider == .codex ? "hooks.json" : "settings.json" }
    @State private var hookInstalled = false
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section {
                Toggle(AgentText.t("监控 AI 任务", "Monitor AI tasks"), isOn: $store.enabled)
                Text(AgentText.t("读取本机 Codex 和 Claude Code 的任务记录，按项目显示并行任务；无归属时显示根目录名称。", "Follow local Codex and Claude Code task records by project. Unassigned tasks use their root folder."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(AgentText.t("打开任务监控", "Open task monitor")) { AgentActivityWindow.shared.show() }
            } header: { Text(AgentText.t("任务监控", "Task monitoring")) }
            Section {
                Picker(AgentText.t("保留时间", "Keep history for"), selection: $store.historyWindow) {
                    ForEach(AgentHistoryWindow.allCases, id: \.self) { window in
                        Text(window == .oneDay ? AgentText.t("1 天", "1 day") : AgentText.t("\(window.rawValue) 小时", "\(window.rawValue) hour" + (window.rawValue == 1 ? "" : "s")))
                            .tag(window)
                    }
                }
                Text(AgentText.t("已读任务仍保留在列表中，默认保留最近 5 小时。进行中和等待处理的任务不受时间限制；每个会话只显示最新状态。", "Read tasks stay in the list, with the last 5 hours kept by default. Working and waiting tasks have no time limit; each conversation shows its latest state."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text(AgentText.t("任务历史", "Task history")) }
            Section {
                Toggle(AgentText.t("完成和等待时发送系统通知", "Notify when finished or waiting"), isOn: Binding(get: { store.notifications }, set: { enabled in
                    if enabled { Task { await store.requestNotifications() } } else { store.notifications = false }
                }))
                Text(AgentText.t("刘海始终保留进行中和待处理任务的摘要。系统通知可以额外提醒你，首次启动不会重播历史通知。", "The notch keeps a summary of active tasks. Optional system notifications alert you to changes; old notifications are not replayed on launch."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text(AgentText.t("提醒", "Notifications")) }
            Section {
                Picker(AgentText.t("连接到", "Connect to"), selection: $provider) {
                    Text("Codex").tag(AgentProvider.codex)
                    Text("Claude Code").tag(AgentProvider.claude)
                }.onChange(of: provider) { _, _ in message = nil; checkHooks() }
                Label(hookInstalled ? AgentText.t("事件连接已安装", "Event connection installed") : AgentText.t("基础监控已就绪", "Basic monitoring is ready"),
                      systemImage: hookInstalled ? "link" : "eye")
                Text(AgentText.t("基础监控自动读取任务状态。要及时识别“等待批准”，可安装事件连接；安装后需在相应应用中审阅并信任 QuotaNotch 的 hooks。未信任时基础监控仍可用。", "Basic monitoring reads local task activity automatically. Install the event connection for prompt approval-wait detection, then review and trust the QuotaNotch hooks in the selected app. Basic monitoring works without trusted hooks."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(hookInstalled ? AgentText.t("更新事件连接", "Update event connection") : AgentText.t("安装事件连接", "Install event connection")) { updateHooks(install: true) }
                    if hookInstalled { Button(AgentText.t("移除", "Remove")) { updateHooks(install: false) } }
                }.disabled(busy)
                if hookInstalled {
                    Text(AgentText.t("在相应应用中审阅事件连接，随后重新打开任务。连接不会代替你批准任何操作。", "Review the event connection in the selected app, then reopen its task. The connection never approves operations for you."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let message { Text(message).font(.callout).fixedSize(horizontal: false, vertical: true) }
            } header: { Text(AgentText.t("等待批准的识别", "Approval-wait detection")) }
            Section {
                Text(store.home.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(store.claudeHome.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button(AgentText.t("选择 Codex 数据目录…", "Choose Codex data folder…")) { chooseHome() }
                Text(AgentText.t("仅在本机读取项目、任务名称和状态；不上传对话内容。远程 SSH、容器或云端任务只有在本机保留活动记录时才能显示。", "Reads project names, task titles and status locally; no conversation uploads. Remote SSH, container and cloud tasks appear only when their activity is recorded on this Mac."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.truncated { Text(AgentText.t("任务记录较多，当前显示数量已达上限。", "The task record limit has been reached.")).foregroundStyle(.orange) }
            } header: { Text(AgentText.t("数据来源", "Data source")) }
        }
        .navigationTitle(AgentText.t("任务监控", "Task monitor"))
        .onAppear { checkHooks() }
    }
    private func checkHooks() {
        let data = try? Data(contentsOf: configHome.appendingPathComponent(configFile))
        hookInstalled = data.flatMap { String(data: $0, encoding: .utf8) }?.contains(AgentHookConfiguration.marker) == true
    }
    private func updateHooks(install: Bool) {
        busy = true
        defer { busy = false }
        do {
            let fm = FileManager.default
            let config = configHome.appendingPathComponent(configFile).resolvingSymlinksInPath()
            let previous = fm.fileExists(atPath: config.path) ? try Data(contentsOf: config) : nil
            guard previous == nil || previous!.count < 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let support = AgentActivityStore.support
            try fm.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let helper = support.appendingPathComponent("QuotaNotchMonitorHook")
            if install {
                let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QuotaNotchMonitorHook")
                let binary = try Data(contentsOf: bundled)
                try binary.write(to: helper, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            }
            let updated = try AgentHookConfiguration.updating(previous, helper: install ? helper.path : nil,
                eventDirectory: support.appendingPathComponent(provider == .codex ? "events" : "claude-events").path, provider: provider)
            if let previous {
                guard try Data(contentsOf: config) == previous else { throw CocoaError(.fileWriteFileExists) }
                try previous.write(to: support.appendingPathComponent("\(provider.rawValue)-hooks-before-quotanotch.json"), options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: support.appendingPathComponent("\(provider.rawValue)-hooks-before-quotanotch.json").path)
            }
            try fm.createDirectory(at: configHome, withIntermediateDirectories: true)
            try updated.write(to: config, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
            message = install ? AgentText.t("已安装。请在相应应用审阅并信任连接，等待批准的检测才会生效。", "Installed. Review and trust the connection in the selected app to enable approval-wait detection.") : AgentText.t("已移除 QuotaNotch 的事件连接，其他配置已保留。", "Removed QuotaNotch hooks; other configuration is preserved.")
            checkHooks()
        } catch { message = error.localizedDescription }
    }
    private func chooseHome() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.showsHiddenFiles = true; panel.directoryURL = store.home
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "agentMonitorCodexHome")
            message = AgentText.t("数据目录已保存，重启 QuotaNotch 后生效。", "Data folder saved. Restart QuotaNotch to apply.")
        }
    }
}
