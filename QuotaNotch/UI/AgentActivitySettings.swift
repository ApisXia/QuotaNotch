// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct AgentActivitySettings: View {
    @ObservedObject private var store = AgentActivityStore.shared
    @State private var hookInstalled = false
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section {
                Toggle(AgentText.t("监控 Codex 任务", "Monitor Codex tasks"), isOn: $store.enabled)
                Text(AgentText.t("支持本机 Codex 桌面端与 VS Code 的 Codex 扩展。按项目显示并行任务，跟随项目改名；无归属时显示根目录名称。", "Follow parallel tasks in the local Codex app and Codex VS Code extension. Project names follow Codex; unassigned tasks use their root folder."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(AgentText.t("打开任务监控", "Open task monitor")) { AgentActivityWindow.shared.show() }
            } header: { Text(AgentText.t("任务监控", "Task monitoring")) }
            Section {
                Toggle(AgentText.t("完成和等待时发送系统通知", "Notify when finished or waiting"), isOn: Binding(get: { store.notifications }, set: { enabled in
                    if enabled { Task { await store.requestNotifications() } } else { store.notifications = false }
                }))
                Text(AgentText.t("刘海始终保留进行中和待处理任务的摘要。系统通知可以额外提醒你，首次启动不会重播历史通知。", "The notch keeps a summary of active tasks. Optional system notifications alert you to changes; old notifications are not replayed on launch."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text(AgentText.t("提醒", "Notifications")) }
            Section {
                Label(hookInstalled ? AgentText.t("事件连接已安装", "Event connection installed") : AgentText.t("基础监控已就绪", "Basic monitoring is ready"),
                      systemImage: hookInstalled ? "link" : "eye")
                Text(AgentText.t("基础监控自动读取任务状态。要及时识别“等待批准”，可安装事件连接；安装后需在 Codex 中审阅并信任 QuotaNotch 的 hooks。未信任时基础监控仍可用。", "Basic monitoring reads local task activity automatically. Install the event connection for prompt approval-wait detection, then review and trust the QuotaNotch hooks in Codex. Basic monitoring works without trusted hooks."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(hookInstalled ? AgentText.t("更新事件连接", "Update event connection") : AgentText.t("安装事件连接", "Install event connection")) { updateHooks(install: true) }
                    if hookInstalled { Button(AgentText.t("移除", "Remove")) { updateHooks(install: false) } }
                }.disabled(busy)
                if hookInstalled {
                    Text(AgentText.t("在 Codex CLI 输入 /hooks 审阅连接，随后重新打开桌面端或扩展中的任务。连接不会代替你批准任何操作。", "Review the connection with /hooks in Codex CLI, then reopen the task in the app or extension. The connection never approves operations for you."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let message { Text(message).font(.callout).fixedSize(horizontal: false, vertical: true) }
            } header: { Text(AgentText.t("等待批准的识别", "Approval-wait detection")) }
            Section {
                Text(store.home.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button(AgentText.t("选择 Codex 数据目录…", "Choose Codex data folder…")) { chooseHome() }
                Text(AgentText.t("仅在本机读取项目、任务名称和状态；不上传对话内容。远程 SSH、容器或云端任务只有在本机保留活动记录时才能显示。", "Reads project names, task titles and status locally; no conversation uploads. Remote SSH, container and cloud tasks appear only when their activity is recorded on this Mac."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.truncated { Text(AgentText.t("当前仅显示最近 2000 条任务记录。", "Showing the 2,000 most recent task records.")).foregroundStyle(.orange) }
            } header: { Text(AgentText.t("数据来源", "Data source")) }
        }
        .navigationTitle(AgentText.t("任务监控", "Task monitor"))
        .onAppear { checkHooks() }
    }
    private func checkHooks() {
        let data = try? Data(contentsOf: store.home.appendingPathComponent("hooks.json"))
        hookInstalled = data.flatMap { String(data: $0, encoding: .utf8) }?.contains(AgentHookConfiguration.marker) == true
    }
    private func updateHooks(install: Bool) {
        busy = true
        defer { busy = false }
        do {
            let fm = FileManager.default
            let config = store.home.appendingPathComponent("hooks.json").resolvingSymlinksInPath()
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
                eventDirectory: support.appendingPathComponent("events").path)
            if let previous {
                guard try Data(contentsOf: config) == previous else { throw CocoaError(.fileWriteFileExists) }
                try previous.write(to: support.appendingPathComponent("hooks-before-quotanotch.json"), options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: support.appendingPathComponent("hooks-before-quotanotch.json").path)
            }
            try fm.createDirectory(at: store.home, withIntermediateDirectories: true)
            try updated.write(to: config, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
            message = install ? AgentText.t("已安装。请在 Codex 审阅并信任连接，等待批准的检测才会生效。", "Installed. Review and trust the connection in Codex to enable approval-wait detection.") : AgentText.t("已移除 QuotaNotch 的事件连接，其他配置已保留。", "Removed QuotaNotch hooks; other configuration is preserved.")
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
