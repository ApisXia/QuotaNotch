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
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                pinSettings
                    .fixedSize(horizontal: false, vertical: true)
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
        let isPinned = store.pins.selected == pin
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
            Button {
                store.updatePins { $0.selected = isPinned ? nil : pin }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? provider.accent : .gray)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "取消固定" : "固定此窗口（替换当前选择）")
            .accessibilityLabel("\(provider.title) \(window.title)，\(isPinned ? "取消固定" : "固定")")
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var pinnedTitle: String {
        guard let pin = store.pins.selected, let provider = pin.provider else { return "选择固定额度" }
        return "\(provider.title) · \(store.window(for: pin)?.title ?? "已固定窗口")"
    }

    /// Outside ScrollView: controls stay in one stationary row.
    private var pinSettings: some View {
        HStack(spacing: 14) {
            Menu {
                Button("不固定") { store.updatePins { $0.selected = nil } }
                Divider()
                ForEach(QuotaProvider.allCases) { item in
                    Section(item.title) {
                        ForEach(store.results[item]?.snapshot?.windows ?? []) { window in
                            let pin = QuotaPin(providerID: item.rawValue, windowID: window.id)
                            Button {
                                store.updatePins { $0.selected = pin }
                            } label: {
                                if store.pins.selected == pin {
                                    Label(window.title, systemImage: "checkmark")
                                } else { Text(window.title) }
                            }
                        }
                    }
                }
            } label: {
                Label(pinnedTitle, systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("固定一个额度窗口，与音乐共享刘海")
            Button { Task { await store.refresh() } } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.refreshing).help("刷新（遵守查询冷却）")
            .fixedSize()
            Button { store.setEnabled(false) } label: {
                Label("暂停", systemImage: "pause")
            }
            .help("暂停用量监控")
            .fixedSize()
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One selection shares the physical cutout with music. Equal wings keep it centered.
@MainActor
struct QuotaPinnedWings: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var music = MusicManager.shared
    let centerWidth: CGFloat
    let height: CGFloat
    let showsMusic: Bool
    let useVisualizer: Bool
    let albumArtNamespace: Namespace.ID
    let onSelect: (QuotaProvider) -> Void
    let onMusic: () -> Void
    static let wingWidth: CGFloat = 88

    private var iconSize: CGFloat { min(26, max(12, height - 10)) }

    var body: some View {
        if let pin = store.pins.selected, let provider = pin.provider {
            HStack(spacing: 0) {
                Button {
                    if showsMusic { onMusic() } else { onSelect(provider) }
                } label: {
                    Group {
                        if showsMusic { albumWithActivity }
                        else {
                            Image(systemName: provider.symbol)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(provider.accent)
                                .frame(width: iconSize, height: iconSize)
                        }
                    }
                    .frame(width: Self.wingWidth, height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsMusic ? "打开音乐" : "\(provider.title) · 打开额度")
                .accessibilityLabel(showsMusic ? "打开音乐" : "打开\(provider.title)额度")

                Color.clear.frame(width: centerWidth, height: height)

                Button { onSelect(provider) } label: {
                    quotaIndicator(pin, provider: provider)
                        .frame(width: Self.wingWidth, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(provider.title) · \(store.window(for: pin)?.title ?? "等待额度") · 点击查看")
                .accessibilityLabel("\(provider.title) \(store.window(for: pin)?.title ?? "额度")")
                .accessibilityValue(reading(for: pin))
            }
            .frame(height: height)
            .animation(.smooth(duration: 0.25), value: showsMusic)
        }
    }

    private var albumWithActivity: some View {
        Image(nsImage: music.albumArt)
            .resizable().scaledToFill()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if useVisualizer {
                        AudioSpectrumView(isPlaying: $music.isPlaying)
                    } else {
                        LottieAnimationContainer()
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 12, height: 8)
                .padding(2)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                .offset(x: 3, y: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    private func reading(for pin: QuotaPin) -> String {
        guard let window = store.window(for: pin) else { return "额度未知" }
        let stale = pin.provider.flatMap { store.results[$0]?.failure } != nil
        return "剩余 \(Int(window.remainingPercent.rounded()))%\(stale ? "，旧数据" : "")"
    }

    private func quotaIndicator(_ pin: QuotaPin, provider: QuotaProvider) -> some View {
        let window = store.window(for: pin)
        let failed = store.results[provider]?.failure != nil
        let color: Color = failed ? .gray : provider.accent
        return HStack(spacing: 5) {
            if showsMusic {
                Image(systemName: provider.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
            }
            Capsule()
                .fill(.white.opacity(0.14))
                .frame(width: showsMusic ? 25 : 34, height: 4)
                .overlay(alignment: .leading) {
                    if let window {
                        Capsule().fill(color)
                            .frame(width: (showsMusic ? 25 : 34) * window.remainingPercent / 100, height: 4)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: window?.remainingPercent)
            VStack(spacing: 0) {
                if let window {
                    Text("\(window.remainingPercent, specifier: "%.0f")%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else { Text("—").font(.system(size: 11)) }
                if failed {
                    Text(window == nil ? "!" : "旧")
                        .font(.system(size: 7)).foregroundStyle(.orange)
                }
            }
            .foregroundStyle(failed ? .gray : .white)
        }
        .accessibilityHidden(true)
    }
}
