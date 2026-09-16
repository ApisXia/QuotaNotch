// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Defaults
import KeyboardShortcuts

struct QuotaPreferences: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @AppStorage("quotaComfortable") private var comfortable = true
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
    }

    private var monitoringSection: some View {
        Section("监控") {
            Toggle("启用额度监控", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
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
                    if store.providerEnabled(provider) {
                        Text(LocalizedStringKey(store.results[provider]?.failure?.message ??
                             (store.results[provider]?.snapshot == nil ? "等待查询" : "已连接")))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(LocalizedStringKey(provider.loginHint)).font(.caption).foregroundStyle(.secondary)
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
                Button("取消固定额度") { store.updatePins { $0.selected = nil } }
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
            ForEach(store.visibleProviders) { provider in
                ForEach(store.results[provider]?.snapshot?.windows ?? []) { window in
                    candidateRow(provider: provider, window: window)
                }
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
            Picker("低额度阈值", selection: $threshold) {
                Text("10%").tag(10.0)
                Text("20%").tag(20.0)
                Text("30%").tag(30.0)
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

    private func candidateRow(provider: QuotaProvider, window: QuotaWindow) -> some View {
        let pin = QuotaPin(providerID: provider.rawValue, windowID: window.id)
        let selected = Binding<Bool>(get: { store.pins.candidates.contains(pin) }, set: { checked in
            store.updatePins { pins in
                pins.candidates.removeAll { $0 == pin }
                if checked { pins.candidates.append(pin) }
            }
        })
        return Toggle(provider.title + " · " + window.localizedTitle, isOn: selected)
    }

}

struct QuotaAppearancePreferences: View {
    @State private var section = "外观"
    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分组", selection: $section) {
                Text("外观").tag("外观")
                Text("系统提示").tag("系统提示")
                Text("电池").tag("电池")
                Text("高级").tag("高级")
            }
            .pickerStyle(.segmented).padding()
            Group {
                switch section {
                case "系统提示": HUD()
                case "电池": Charge()
                case "高级": Advanced()
                default: Appearance()
                }
            }
        }
        .navigationTitle("外观与提示")
    }
}
