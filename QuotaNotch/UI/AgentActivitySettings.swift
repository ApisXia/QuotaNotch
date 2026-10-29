// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Task preferences. Connecting Claude Code / Codex (including the optional event hooks)
/// lives in Settings → Connections.
struct AgentActivitySettings: View {
    @ObservedObject private var store = AgentActivityStore.shared
    @ObservedObject private var hooks = HookConnection.shared
    var body: some View {
        Form {
            Section {
                Toggle(AgentText.t("在刘海中显示 AI 任务", "Show AI tasks in the notch"), isOn: $store.enabled)
                Text(AgentText.t("按项目显示本机 Codex 和 Claude Code 的任务进度。", "Shows local Codex and Claude Code task progress by project."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(AgentText.t("打开任务窗口", "Open task window")) { AgentActivityWindow.shared.show() }
                if store.truncated { Text(AgentText.t("任务记录较多，当前显示数量已达上限。", "The task record limit has been reached.")).foregroundStyle(.orange) }
            }
            Section {
                Picker(AgentText.t("已读任务保留", "Keep read tasks for"), selection: $store.historyWindow) {
                    ForEach(AgentHistoryWindow.allCases, id: \.self) { window in
                        Text(window == .oneDay ? AgentText.t("1 天", "1 day") : AgentText.t("\(window.rawValue) 小时", "\(window.rawValue) hour" + (window.rawValue == 1 ? "" : "s")))
                            .tag(window)
                    }
                }
                Toggle(AgentText.t("完成或等你处理时发送通知", "Notify when a task finishes or needs you"), isOn: Binding(get: { store.notifications }, set: { enabled in
                    if enabled { Task { await store.requestNotifications() } } else { store.notifications = false }
                }))
                Text(AgentText.t("进行中和等你处理的任务一直显示。通知只包含项目和状态。", "Working and waiting tasks always stay visible. Notifications show only the project and status."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if hooks.installed.values.contains(true) == false {
                Section {
                    HStack {
                        Text(AgentText.t("想在任务等你批准时立即收到提示？在“连接”中安装任务事件。", "Want an instant cue when a task waits for approval? Install task events in Connections."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(AgentText.t("前往连接", "Open Connections")) {
                            UserDefaults.standard.set("Connections", forKey: "settingsSelectedTab")
                        }
                    }
                }
            }
        }
        .navigationTitle(AgentText.t("任务", "Tasks"))
        .task { hooks.check() }
    }
}
