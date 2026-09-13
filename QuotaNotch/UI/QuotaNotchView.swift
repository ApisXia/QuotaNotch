// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
final class QuotaNotchStore: ObservableObject {
    static let shared = QuotaNotchStore()
    @Published private(set) var results: [QuotaProvider: QuotaResult] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "quotaNotchEnabled")
    private let client = QuotaClient()
    private var polling: Task<Void, Never>?

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "quotaNotchEnabled")
        if value { start() }
        else {
            polling?.cancel()
            polling = nil
            results = [:]
        }
    }

    func start() {
        guard enabled, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { break }
            }
        }
    }

    func refresh() async {
        guard enabled, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        async let claude = client.refresh(.claude)
        async let codex = client.refresh(.codex)
        let values = await (claude, codex)
        guard enabled, !Task.isCancelled else { return }
        results = [.claude: values.0, .codex: values.1]
    }
}

/// Rendered inside ContentView's original NotchLayout, never in a separate menu-bar window.
@MainActor
struct QuotaNotchView: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @State private var provider: QuotaProvider = .claude

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.enabled {
                HStack {
                    ForEach(QuotaProvider.allCases) { item in
                        Button {
                            provider = item
                        } label: {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(provider == item ? Color.white.opacity(0.16) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(provider == item ? .isSelected : [])
                    }
                    Spacer(minLength: 4)
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.refreshing)
                    .help("刷新（遵守缓存和服务端限流）")
                    .accessibilityLabel("刷新用量")
                    Button { store.setEnabled(false) } label: {
                        Image(systemName: "pause.circle")
                    }
                    .help("停止读取用量")
                    .accessibilityLabel("停止读取用量")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let result = store.results[provider] {
                            if let failure = result.failure {
                                Text(failure.message).foregroundStyle(.orange).font(.caption)
                                if failure == .notSignedIn || failure == .expired || failure == .credentialsUnavailable {
                                    Text(provider.loginHint).font(.caption).foregroundStyle(.secondary)
                                    if provider == .codex {
                                        Text("需本机 CLI 的 auth.json；仅浏览器登录或 API key 不适用。")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if let snapshot = result.snapshot {
                                ForEach(snapshot.windows) { window in
                                    windowRow(window, stale: result.failure != nil)
                                }
                                HStack {
                                    Text(result.failure == nil ? "更新于" : "上次成功（旧数据）")
                                    Text(snapshot.fetchedAt, style: .time)
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("下次可查询")
                                Text(result.nextAttempt, style: .time)
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            ProgressView("正在读取本机登录状态…").font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("QuotaNotch · AI 用量").font(.headline)
                        Text("在此刘海中查看 Claude / Codex 剩余额度和重置时间。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("启用后读取本机 CLI 登录凭据，并向对应服务查询。凭据不会上传到 GitHub 或云端 workspace。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("启用本机用量监控") { store.setEnabled(true) }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .task { store.start() }
    }

    private func windowRow(_ window: QuotaWindow, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.title)
                Spacer()
                Text("剩余 \(window.remainingPercent, specifier: "%.0f")%")
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(stale ? .gray : (window.remainingPercent < 20 ? .orange : .white))
                .accessibilityLabel("\(window.title)剩余额度")
            HStack(spacing: 4) {
                if let reset = window.resetsAt {
                    Text("重置")
                    Text(reset, style: .date)
                    Text(reset, style: .time)
                } else {
                    Text("服务端未提供重置时间")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
