// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaProvider {
    var accent: Color { self == .claude ? Color(red: 0.91, green: 0.60, blue: 0.43) : Color(red: 0.48, green: 0.81, blue: 0.70) }
    var symbol: String { self == .claude ? "sun.max.fill" : "chevron.left.forwardslash.chevron.right" }
}

/// A missing reading is an empty track and a dash, never a full or zero quota claim.
struct QuotaRing: View {
    let provider: QuotaProvider
    let percent: Double?
    var stale = false
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: size > 30 ? 3 : 2)
            if let percent {
                Circle().trim(from: 0, to: max(0, min(1, percent / 100)))
                    .stroke(stale ? Color.gray : provider.accent,
                            style: StrokeStyle(lineWidth: size > 30 ? 3 : 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: provider.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(stale ? .gray : provider.accent)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.35), value: percent)
        .accessibilityHidden(true)
    }
}

@MainActor
struct QuotaNotchView: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    private var provider: QuotaProvider { store.selectedProvider }

    var body: some View {
        VStack(spacing: 12) {
            if store.enabled {
                HStack(spacing: 10) {
                    ForEach(QuotaProvider.allCases) { item in providerTile(item) }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let result = store.results[provider] {
                            if let error = result.failure {
                                Label(error.message, systemImage: "exclamationmark.circle")
                                    .font(.caption).foregroundStyle(.orange)
                                if error == .notSignedIn || error == .expired || error == .credentialsUnavailable {
                                    Text(provider.loginHint).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let snapshot = result.snapshot {
                                ForEach(snapshot.windows) { window in
                                    windowCard(window, stale: result.failure != nil)
                                }
                                HStack(spacing: 4) {
                                    Text(result.failure == nil ? "更新于" : "旧数据 · 上次成功")
                                    Text(snapshot.fetchedAt, style: .time)
                                    Spacer()
                                    Text("下次查询")
                                    Text(result.nextAttempt, style: .time)
                                }
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            } else {
                                Text("等待可用额度 · 不显示估算数据")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            ProgressView("正在读取…").controlSize(.small)
                        }
                        pinSettings
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer(minLength: 0)
                HStack(spacing: 20) {
                    QuotaRing(provider: .claude, percent: nil)
                    QuotaRing(provider: .codex, percent: nil)
                }
                Text("让额度留在刘海边上").font(.headline)
                Text("读取这台 Mac 的 Claude / Codex 登录状态，查看剩余额度。")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("启用本机用量监控") { store.setEnabled(true) }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .task { store.start() }
    }

    private func providerTile(_ item: QuotaProvider) -> some View {
        let result = store.results[item]
        let window = result?.snapshot?.windows.first
        return Button { store.selectedProvider = item } label: {
            HStack(spacing: 10) {
                QuotaRing(provider: item, percent: window?.remainingPercent, stale: result?.failure != nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 12, weight: .semibold))
                    if let window {
                        Text("\(window.remainingPercent, specifier: "%.0f")%")
                            .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("\(window.title)剩余\(result?.failure != nil ? " · 旧" : "")")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Text("—").font(.system(size: 22, weight: .medium))
                        Text(result?.failure == nil ? "读取中" : "需查看状态")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(provider == item ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(provider == item ? item.accent.opacity(0.45) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(provider == item ? .isSelected : [])
    }

    private func windowCard(_ window: QuotaWindow, stale: Bool) -> some View {
        let pin = QuotaPin(providerID: provider.rawValue, windowID: window.id)
        let position = store.pins.left == pin ? "左侧" : (store.pins.right == pin ? "右侧" : "固定")
        return HStack(spacing: 12) {
            QuotaRing(provider: provider, percent: window.remainingPercent, stale: stale, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(window.title).font(.system(size: 12, weight: .semibold))
                    Text("剩余 \(window.remainingPercent, specifier: "%.0f")%")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(stale ? .gray : provider.accent)
                }
                HStack(spacing: 3) {
                    if let reset = window.resetsAt {
                        Text("重置")
                        Text(reset, style: .date)
                        Text(reset, style: .time)
                    } else { Text("重置时间未知") }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("固定到左侧") { store.updatePins { $0.assign(pin, toLeft: true) } }
                Button("固定到右侧") { store.updatePins { $0.assign(pin, toLeft: false) } }
                if store.pins.left == pin || store.pins.right == pin {
                    Button("取消固定") { store.updatePins { $0.remove(pin) } }
                }
            } label: {
                Label(position, systemImage: "pin.fill").font(.system(size: 10, weight: .medium))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("\(provider.title) \(window.title)，\(position)")
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var pinSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("刘海固定").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.refreshing).help("刷新（遵守查询冷却）").accessibilityLabel("刷新额度")
                Button { store.setEnabled(false) } label: { Image(systemName: "pause.circle") }
                    .help("暂停监控").accessibilityLabel("暂停监控")
            }
            Text("左右各一个窗口；固定新窗口会替换该侧显示。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle("音乐播放时暂让位", isOn: Binding(
                get: { store.pins.yieldToMusic },
                set: { value in store.updatePins { $0.yieldToMusic = value } }
            ))
            .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            if store.pins.hasPins {
                Button("清除两侧固定") { store.updatePins { $0.left = nil; $0.right = nil } }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

/// Equal-width wings keep the physical camera cutout centered even with a single pin.
@MainActor
struct QuotaPinnedWings: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    let centerWidth: CGFloat
    let height: CGFloat
    let onSelect: (QuotaProvider) -> Void
    static let wingWidth: CGFloat = 62

    var body: some View {
        HStack(spacing: 0) {
            wing(store.pins.left)
            Color.clear.frame(width: centerWidth, height: height)
            wing(store.pins.right)
        }
        .frame(height: height)
    }

    @ViewBuilder private func wing(_ pin: QuotaPin?) -> some View {
        if let pin, let provider = pin.provider {
            let window = store.window(for: pin)
            let failed = store.results[provider]?.failure != nil
            Button { onSelect(provider) } label: {
                HStack(spacing: 5) {
                    QuotaRing(provider: provider, percent: window?.remainingPercent, stale: failed,
                              size: min(24, max(12, height - 8)))
                    VStack(spacing: 0) {
                        if let window {
                            Text("\(window.remainingPercent, specifier: "%.0f")%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        } else { Text("—").font(.system(size: 11)) }
                        if failed { Text(window == nil ? "!" : "旧").font(.system(size: 7)).foregroundStyle(.orange) }
                    }
                }
                .frame(width: Self.wingWidth, height: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(provider.title) · \(window?.title ?? "等待额度")\(failed ? " · 状态异常，点击查看" : " · 点击查看")")
            .accessibilityLabel("\(provider.title) \(window?.title ?? "额度未知")\(failed ? "，数据异常" : "")")
        } else {
            Color.clear.frame(width: Self.wingWidth, height: height)
        }
    }
}
