// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Defaults
import KeyboardShortcuts

struct QuotaPreferences: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    var body: some View {
        Form {
            Section("监控") {
                Toggle("启用额度监控", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
                Text("仅从本机登录状态读取额度；暂停的服务不会查询。")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                            Text(store.results[provider]?.failure?.message ??
                                 (store.results[provider]?.snapshot == nil ? "等待查询" : "已连接"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(provider.loginHint).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 3)
                }
                Text("Gemini CLI 仅适用于仍有效的 Code Assist 登录，不代表 Gemini 网页版或 AI Studio 的额度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("刘海显示") {
                Toggle("圆环显示数字", isOn: Binding(get: { store.pins.showsNumbers },
                    set: { value in store.updatePins { $0.showsNumbers = value } }))
                Text("数字表示剩余百分比。固定窗口在 AI 额度页选择；音乐播放时左侧显示封面与动效，右侧显示额度。")
                    .font(.caption).foregroundStyle(.secondary)
                if store.pins.selected != nil {
                    Button("取消固定额度") { store.updatePins { $0.selected = nil } }
                }
            }
        }
        .navigationTitle("AI 额度")
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
