// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Defaults
import KeyboardShortcuts

struct QuotaPreferences: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var claude = ClaudeConnection.shared
    @AppStorage(NotchUISize.defaultsKey) private var sizeRaw = NotchUISize.current.rawValue
    @AppStorage("quotaNotifications") private var notifications = false
    @AppStorage("quotaAlertThreshold") private var threshold = 20.0
    @AppStorage(QuotaPetKind.defaultsKey) private var petRaw = QuotaPetKind.defaultKind.rawValue
    @AppStorage(QuotaPetTint.defaultsKey) private var tintRaw = QuotaPetTint.original.rawValue
    @AppStorage(QuotaPetEffect.defaultsKey) private var effectRaw = QuotaPetEffect.soft.rawValue
    @AppStorage(QuotaPetHoliday.defaultsKey) private var holidaysRaw = "auto"
    @AppStorage(QuotaPetHoliday.birthdayKey) private var birthday = ""
    private var pet: QuotaPetKind { QuotaPetKind.choice(petRaw) }
    private var size: NotchUISize { NotchUISize.stored(sizeRaw, legacyComfortable: false) }
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
            VStack(alignment: .leading, spacing: 8) {
                Text("宠物")
                QuotaPetPicker(selection: Binding(get: { QuotaPetKind.choice(petRaw) }, set: { petRaw = $0.rawValue }),
                               provider: store.activePin?.provider ?? .claude)
            }
            .padding(.vertical, 3)
            SettingsField("宠物配色") {
                Picker("宠物配色", selection: $tintRaw) {
                    Text("原色").tag(QuotaPetTint.original.rawValue)
                    Text("按服务着色").tag(QuotaPetTint.service.rawValue)
                }
            }
            SettingsField("提示效果") {
                Picker("提示效果", selection: $effectRaw) {
                    Text("柔光").tag(QuotaPetEffect.soft.rawValue)
                    Text("像素").tag(QuotaPetEffect.pixel.rawValue)
                }
            }
            SettingsField("节日装扮") {
                Picker("节日装扮", selection: $holidaysRaw) {
                    Text("自动").tag("auto")
                    Text("关闭").tag("off")
                }
            }
            if holidaysRaw != "off" { birthdayRow }
            petPreview
            sizeRow
        }
    }

    /// Party hats on the user's birthday, if they set one ("MM-dd").
    private var birthdayRow: some View {
        let calendar = Calendar.current
        let parts = birthday.split(separator: "-").compactMap { Int($0) }
        let date = Binding<Date>(
            get: {
                guard parts.count == 2 else { return Date() }
                var day = calendar.dateComponents([.year], from: Date())
                day.month = parts[0]; day.day = parts[1]
                return calendar.date(from: day) ?? Date()
            },
            set: { value in
                let day = calendar.dateComponents([.month, .day], from: value)
                birthday = String(format: "%02d-%02d", day.month ?? 1, day.day ?? 1)
            })
        return HStack {
            Toggle("生日那天戴派对帽", isOn: Binding(get: { parts.count == 2 }, set: { on in
                if on { date.wrappedValue = Date() } else { birthday = "" }
            }))
            Spacer()
            if parts.count == 2 {
                DatePicker("生日", selection: date, displayedComponents: .date).labelsHidden()
            }
        }
    }

    /// Three steps: standard keeps the original sizes and only enlarges the pet; small and
    /// large also resize the closed icons and the opened panel.
    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("大小")
            Slider(value: Binding(get: { Double(size.index) },
                                  set: { sizeRaw = NotchUISize.allCases[min(2, max(0, Int($0.rounded())))].rawValue }),
                   in: 0...2, step: 1)
                .labelsHidden()
            HStack {
                Text("小"); Spacer(); Text("标准"); Spacer(); Text("大")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("标准：只放大宠物。小和大会一起调整刘海里的图标和展开后的面板。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    /// The chosen pet in each quota state, drawn twice the notch size.
    private var petPreview: some View {
        let provider = store.activePin?.provider ?? .claude
        let samples: [(QuotaPetMood, Double, LocalizedStringKey)] = [
            (.idle, 72, "充足"), (.working, 64, "正在消耗"), (.pacing, 41, "用得偏快"),
            (.low, 12, "低于 20%"), (.empty, 0, "用完"), (.refilled, 100, "刚重置")
        ]
        let taskSamples: [(QuotaPetMood, QuotaPetSignal, LocalizedStringKey)] = [
            (.working, .running, "任务运行中"), (.needsYou, .waiting, "等你批准"), (.celebrate, .none, "任务完成")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    VStack(spacing: 4) {
                        QuotaPetView(kind: pet, size: .widget, provider: provider,
                                     window: QuotaWindow(id: "preview", title: "", remainingPercent: sample.1, resetsAt: nil),
                                     stale: false, scale: 2, fixedMood: sample.0)
                            .frame(width: 48, height: 40)
                            .background(.black, in: RoundedRectangle(cornerRadius: 8))
                        Text(sample.2).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(taskSamples.enumerated()), id: \.offset) { _, sample in
                    VStack(spacing: 4) {
                        QuotaPetView(kind: pet, size: .widget, provider: provider,
                                     window: QuotaWindow(id: "preview", title: "", remainingPercent: 64, resetsAt: nil),
                                     stale: false, scale: 2, fixedMood: sample.0, fixedSignal: sample.1)
                            .frame(width: 48, height: 40)
                            .padding(.horizontal, 21).padding(.vertical, 6)
                            .background(.black, in: RoundedRectangle(cornerRadius: 8))
                        Text(sample.2).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Text("身上的计量就是剩余额度。任务运行时周围有淡淡的波纹，等你批准时会闪烁；播放音乐时，任务显示在宠物右下角。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
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
