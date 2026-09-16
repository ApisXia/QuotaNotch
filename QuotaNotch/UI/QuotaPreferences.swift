// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Defaults
import KeyboardShortcuts

struct QuotaPreferences: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @AppStorage("quotaComfortable") private var comfortable = false
    @AppStorage("quotaNotifications") private var notifications = false
    @AppStorage("quotaAlertThreshold") private var threshold = 20.0
    @State private var copied = false
    var body: some View {
        Form {
            monitoringSection
            providersSection
            displaySection
            automaticSection
            notificationsSection
            diagnosticsSection
        }
        .navigationTitle("AI 额度")
        .task { await store.refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshNotificationStatus() }
        }
    }

    private var monitoringSection: some View {
        Section("监控") {
            Toggle("启用额度监控", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
            if !store.enabled { SettingsHint("Monitoring is paused. Your services and display preferences are saved.") }
            Text("仅从本机登录状态读取额度；暂停的服务不会查询。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var providersSection: some View {
        Section("服务") {
            ForEach(QuotaProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(get: { store.providerEnabled(provider) },
                                         set: { store.setProvider(provider, enabled: $0) })) {
                        HStack {
                            QuotaBrandMark(brand: provider.brand).frame(width: 18, height: 18)
                            Text(provider.title)
                        }
                    }
                    if !store.enabled {
                        SettingsHint("Monitoring paused")
                    } else if store.providerEnabled(provider) {
                        Text(LocalizedStringKey(store.results[provider]?.failure?.message ??
                             (store.results[provider]?.snapshot == nil ? "等待查询" : "已连接")))
                            .font(.caption).foregroundStyle(.secondary)
                        if store.results[provider]?.snapshot == nil || store.results[provider]?.failure != nil {
                            Text(LocalizedStringKey(provider.loginHint)).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        SettingsHint("此服务已暂停")
                    }
                }.padding(.vertical, 3)
            }
            Text("Gemini CLI 仅适用于仍有效的 Code Assist 登录，不代表 Gemini 网页版或 AI Studio 的额度。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        Section("刘海显示") {
            Toggle("大字模式", isOn: $comfortable)
            Toggle("圆环显示数字", isOn: Binding(get: { store.pins.showsNumbers },
                set: { value in store.updatePins { $0.showsNumbers = value } }))
            Text("数字表示剩余百分比。固定窗口在 AI 额度页选择；音乐播放时左侧显示封面与动效，右侧显示额度。")
                .font(.caption).foregroundStyle(.secondary)
            if store.pins.selected != nil {
                Text("Manual fallback: \(pinTitle(store.pins.selected!))")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Clear manual selection") { store.updatePins { $0.selected = nil } }
            }
        }
    }

    private var automaticSection: some View {
        Section("自动关注") {
            Toggle("自动显示最低剩余额度", isOn: Binding(get: { store.pins.automatic }, set: { value in
                store.updatePins { $0.automatic = value }
            }))
            Text("仅比较选中的额度窗口；旧数据不参与比较。没有可用数据时保留手动固定项。")
                .font(.caption).foregroundStyle(.secondary)
            if store.enabled, let active = store.activePin {
                Text("Currently shown: \(pinTitle(active))")
                    .fixedSize(horizontal: false, vertical: true)
                SettingsHint(store.automaticPin != nil ? "Selected automatically from fresh data." : "Using your manual selection.")
            }
            ForEach(editableCandidates, id: \.self) { pin in candidateRow(pin) }
            if !store.pins.automatic {
                SettingsHint("Candidate selections are saved and apply when automatic selection is enabled.")
            } else if !store.pins.candidates.isEmpty && store.automaticPin == nil {
                SettingsHint("No selected window has fresh data. Your manual selection is used when available.")
            }
            if store.pins.automatic && store.pins.candidates.isEmpty {
                Text("请至少选择一个额度窗口").foregroundStyle(.orange)
            }
        }
    }

    private var notificationsSection: some View {
        Section("额度通知") {
            Toggle("低额度与恢复通知", isOn: Binding(get: { notifications }, set: { value in
                Task { await store.setNotifications(value) }
            }))
            .disabled(store.requestingNotifications)
            SettingsField("低额度阈值") {
                Picker("低额度阈值", selection: $threshold) {
                    Text("10%").tag(10.0)
                    Text("20%").tag(20.0)
                    Text("30%").tag(30.0)
                }
            }.disabled(!notifications)
            if store.notificationsDenied {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
                }
            }
            Text("每个额度周期提醒一次；恢复提醒仅在成功读取到新额度后发送。")
                .font(.caption).foregroundStyle(.secondary)
            if !store.notificationStatus.isEmpty { Text(store.notificationStatus).font(.caption) }
        }
    }

    private var diagnosticsSection: some View {
        Section("连接诊断") {
            Button { store.copyDiagnostics(); copied = true } label: {
                Text(LocalizedStringKey(copied ? "已复制" : "复制诊断信息"))
            }
            Text("仅包含应用、系统版本、连接状态与更新时间，不包含令牌、账户或本机路径。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var editableCandidates: [QuotaPin] {
        let available = store.visibleProviders.flatMap { provider in
            (store.results[provider]?.snapshot?.windows ?? []).map { QuotaPin(providerID: provider.rawValue, windowID: $0.id) }
        }
        return store.pins.editableCandidates(available: available)
    }

    private func pinTitle(_ pin: QuotaPin) -> String {
        let title = store.window(for: pin)?.localizedTitle ?? QuotaText.localized([
            "five_hour": "5 小时", "seven_day": "7 天", "seven_day_sonnet": "Sonnet · 7 天",
            "seven_day_opus": "Opus · 7 天", "primary_window": "主窗口", "secondary_window": "次窗口"
        ][pin.windowID] ?? pin.windowID)
        return (pin.provider?.title ?? pin.providerID) + " · " + title
    }

    private func candidateRow(_ pin: QuotaPin) -> some View {
        let selected = Binding<Bool>(get: { store.pins.candidates.contains(pin) }, set: { checked in
            store.updatePins { pins in
                pins.candidates.removeAll { $0 == pin }
                if checked { pins.candidates.append(pin) }
            }
        })
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: selected) { Text(pinTitle(pin)).fixedSize(horizontal: false, vertical: true) }
            if !store.enabled {
                SettingsHint("Monitoring paused")
            } else if let provider = pin.provider, !store.providerEnabled(provider) {
                SettingsHint("此服务已暂停")
            } else if store.window(for: pin) == nil || pin.provider.map({ store.isStale($0) }) != false {
                SettingsHint("Waiting for fresh data; saved selection is retained.")
            }
        }
    }
}
