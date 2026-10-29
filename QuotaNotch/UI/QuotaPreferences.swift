// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Defaults
import KeyboardShortcuts

struct QuotaPreferences: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var claude = ClaudeConnection.shared
    @AppStorage("quotaComfortable") private var comfortable = false
    @AppStorage("quotaNotifications") private var notifications = false
    @AppStorage("quotaAlertThreshold") private var threshold = 20.0
    var body: some View {
        Form {
            providersSection
            displaySection
            notificationsSection
        }
        .navigationTitle("AI 额度")
        .task { claude.check(); await store.refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            claude.check()
            Task { await store.refreshNotificationStatus() }
        }
    }

    private var providersSection: some View {
        Section {
            ForEach(QuotaProvider.allCases) { provider in
                HStack(alignment: .top) {
                    Toggle(isOn: Binding(get: { store.providerEnabled(provider) },
                                         set: { store.setProvider(provider, enabled: $0) })) {
                        HStack(spacing: 6) {
                            QuotaBrandMark(brand: provider.brand).frame(width: 16, height: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(provider.title)
                                if store.providerEnabled(provider) {
                                    Text(state(provider).text).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if provider == .claude && store.providerEnabled(.claude) && !claude.installed {
                        Button("连接 Claude Code") { claude.setConnected(true) }
                            .buttonStyle(.borderedProminent).controlSize(.small).disabled(claude.busy)
                    }
                }
            }
        } header: { Text("服务") } footer: {
            HStack {
                Text("连接方式、任务事件和诊断都在“连接”中。").font(.caption).foregroundStyle(.secondary)
                Button("前往连接") { UserDefaults.standard.set("Connections", forKey: "settingsSelectedTab") }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private func state(_ provider: QuotaProvider) -> ConnectionState {
        provider == .claude ? claude.state(result: store.results[.claude]) : store.codexState
    }

    private var displaySection: some View {
        Section("刘海显示") {
            SettingsField("收起时显示") {
                Picker("收起时显示", selection: Binding(get: { store.notchChoice }, set: { store.notchChoice = $0 })) {
                    Text("自动（剩余最少的额度）").tag(QuotaNotchStore.NotchChoice.automatic)
                    Text("不显示").tag(QuotaNotchStore.NotchChoice.none)
                    if !choicePins.isEmpty { Divider() }
                    ForEach(choicePins, id: \.self) { pin in
                        Text(verbatim: store.title(for: pin)).tag(QuotaNotchStore.NotchChoice.fixed(pin))
                    }
                }
            }
            Toggle("圆环中显示剩余百分比", isOn: Binding(get: { store.pins.showsNumbers },
                set: { value in store.updatePins { $0.showsNumbers = value } }))
            Toggle("大字模式", isOn: $comfortable)
        }
    }

    /// Windows with readings, plus a saved fixed choice even while its data is missing.
    private var choicePins: [QuotaPin] {
        var pins = store.availablePins
        if case .fixed(let pin) = store.notchChoice, !pins.contains(pin) { pins.append(pin) }
        return pins
    }

    private var notificationsSection: some View {
        Section("低额度通知") {
            Toggle("剩余额度低于阈值时通知", isOn: Binding(get: { notifications }, set: { value in
                Task { await store.setNotifications(value) }
            }))
            .disabled(store.requestingNotifications)
            SettingsField("阈值") {
                Picker("阈值", selection: $threshold) {
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
            Text("每个额度周期最多提醒一次，额度恢复时再提醒一次。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
