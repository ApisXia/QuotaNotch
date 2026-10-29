// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaText {
    /// "3 minutes ago" / "3分钟前", in the language the app bundle actually resolved.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return localized("刚刚") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

enum ConnectionState: Equatable {
    case connected(String)
    case waiting(String)
    case off(String)

    var color: Color {
        switch self {
        case .connected: return .green
        case .waiting: return .orange
        case .off: return .secondary
        }
    }
    var text: String {
        switch self { case .connected(let t), .waiting(let t), .off(let t): return t }
    }
}

/// One line per capability: what it is, its state, and the single action that changes it.
struct ConnectionRow<Actions: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let state: ConnectionState
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(state.color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(state.text).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(.vertical, 2)
    }
}

extension ClaudeConnection {
    func state(result: QuotaResult?) -> ConnectionState {
        guard installed else { return .off(QuotaText.localized("未连接")) }
        if let snapshot = result?.snapshot {
            return .connected(QuotaText.localized("已连接") + " · " + QuotaText.localized("更新于") + " " + QuotaText.relative(snapshot.fetchedAt))
        }
        return .waiting(QuotaText.localized("已连接，在 Claude Code 中发送一条消息后显示额度"))
    }
}

extension QuotaNotchStore {
    var codexState: ConnectionState {
        guard providerEnabled(.codex) else { return .off(QuotaText.localized("此服务已暂停")) }
        let result = results[.codex]
        if let snapshot = result?.snapshot, result?.failure == nil {
            return .connected(QuotaText.localized("已登录") + " · " + QuotaText.localized("更新于") + " " + QuotaText.relative(snapshot.fetchedAt))
        }
        switch result?.failure {
        case nil: return .waiting(QuotaText.localized("正在读取…"))
        case .notSignedIn?, .expired?: return .off(QuotaText.localized("未登录：在终端运行 codex login"))
        case let failure?: return .waiting(failure.message)
        }
    }
}

struct ConnectionsSettings: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var claude = ClaudeConnection.shared
    @ObservedObject private var hooks = HookConnection.shared
    @State private var showClaudeDetails = false
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                ConnectionRow(title: "额度", detail: "读取 Claude Code 状态栏中的 5 小时和 7 天用量，不读取钥匙串或令牌。需要 Pro 或 Max 订阅。",
                              state: claude.state(result: store.results[.claude])) {
                    if claude.installed {
                        Button("断开") { claude.setConnected(false) }.disabled(claude.busy)
                    } else {
                        Button("连接") { claude.setConnected(true) }.buttonStyle(.borderedProminent).disabled(claude.busy)
                    }
                }
                if let message = claude.message { errorText(message) }
                DisclosureGroup("连接会修改什么", isExpanded: $showClaudeDetails) {
                    Text("在 settings.json 的 statusLine 中加入 QuotaNotch 的小程序。原有状态栏命令会保留并照常显示；没有时显示一行剩余额度。断开后文件逐字节恢复。注意：只要设置了状态栏，Claude Code 底部就不再显示部分快捷键提示（如 esc to interrupt）。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                hookRow(.claude)
                pathRow(store: AgentActivityStore.shared.claudeHome.path, choose: nil)
            } header: {
                Label { Text(verbatim: "Claude Code") } icon: { QuotaBrandMark(brand: .claude).frame(width: 14, height: 14) }
            }

            Section {
                ConnectionRow(title: "额度", detail: "读取本机 Codex CLI 的登录状态查询用量，只读不改。",
                              state: store.codexState) {
                    if !store.providerEnabled(.codex) {
                        Button("启用") { store.setProvider(.codex, enabled: true) }
                    }
                }
                hookRow(.codex)
                pathRow(store: AgentActivityStore.shared.home.path) { hooks.chooseCodexHome() }
            } header: {
                Label { Text(verbatim: "Codex") } icon: { QuotaBrandMark(brand: .codex).frame(width: 14, height: 14) }
            }

            Section("诊断") {
                HStack {
                    Text("仅包含应用、系统版本、连接状态与更新时间，不包含令牌、账户或本机路径。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { store.copyDiagnostics(); copied = true } label: {
                        Text(LocalizedStringKey(copied ? "已复制" : "复制诊断信息"))
                    }
                }
            }
        }
        .navigationTitle("连接")
        .task { claude.check(); hooks.check() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            claude.check(); hooks.check()
        }
    }

    @ViewBuilder private func hookRow(_ provider: AgentProvider) -> some View {
        let on = hooks.installed[provider] == true
        ConnectionRow(title: "任务事件（可选）",
                      detail: "任务在等你批准时，刘海能立即提示。不装也能看到任务进度。",
                      state: on ? .connected(QuotaText.localized("已安装")) : .off(QuotaText.localized("未安装"))) {
            Button(LocalizedStringKey(on ? "移除" : "安装")) { hooks.set(provider, installed: !on) }.disabled(hooks.busy)
        }
        if let message = hooks.message[provider] { errorText(message) }
    }

    private func pathRow(store path: String, choose: (() -> Void)?) -> some View {
        HStack {
            Text("数据目录").font(.caption).foregroundStyle(.secondary)
            Text(verbatim: path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer()
            if let choose { Button("更改…", action: choose).controlSize(.small) }
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }
}
