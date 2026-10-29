// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// First-run step: the app is about quota and tasks, so connecting the tools comes first.
struct OnboardingConnectView: View {
    @ObservedObject private var claude = ClaudeConnection.shared
    @ObservedObject private var hooks = HookConnection.shared
    @ObservedObject private var store = QuotaNotchStore.shared
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "link")
                .resizable().scaledToFit().frame(width: 52, height: 52)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 36)
            Text("连接你的 AI 工具").font(.title).fontWeight(.semibold)
            Text("QuotaNotch 在刘海中显示 Claude 和 Codex 的剩余额度与任务进度，全部在本机读取。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 28)

            VStack(spacing: 12) {
                toolRow(brand: .claude, title: "Claude Code", state: claude.state(result: store.results[.claude])) {
                    if claude.installed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("连接") { claude.setConnected(true) }.buttonStyle(.borderedProminent).disabled(claude.busy)
                    }
                }
                toolRow(brand: .codex, title: "Codex", state: store.codexState) { EmptyView() }
                Toggle(isOn: Binding(get: { hooks.installed.values.contains(true) }, set: { on in
                    for provider in [AgentProvider.claude, .codex] where (hooks.installed[provider] == true) != on {
                        hooks.set(provider, installed: on)
                    }
                })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("任务等你批准时立即提示")
                        Text("可选：为 Claude Code 和 Codex 安装任务事件").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch).disabled(hooks.busy)
                if let message = claude.message {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Text("连接 Claude Code 会修改它的 settings.json，随时可以在 设置 → 连接 中断开并恢复。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            Button(LocalizedStringKey(claude.installed ? "继续" : "稍后再说"), action: onContinue)
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow).ignoresSafeArea())
        .task { claude.check(); hooks.check(); store.start() }
    }

    private func toolRow<Trailing: View>(brand: QuotaBrand, title: String, state: ConnectionState,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            QuotaBrandMark(brand: brand).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                Text(state.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing()
        }
    }
}
