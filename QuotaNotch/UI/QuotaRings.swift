// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaProvider {
    var brand: QuotaBrand { self == .claude ? .claude : .codex }
    var accent: Color { brand.color }
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
            QuotaBrandMark(brand: provider.brand, muted: stale)
                .frame(width: size * 0.48, height: size * 0.48)
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
    @State private var page = 0
    private var windows: [QuotaWindow] { store.results[provider]?.snapshot?.windows ?? [] }
    private var pageCount: Int { QuotaWindowPages.count(windows: windows.count) }

    var body: some View {
        VStack(spacing: 8) {
            if store.enabled {
                HStack(spacing: 10) {
                    ForEach(QuotaProvider.allCases) { item in providerTile(item) }
                }
                quotaDetails
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        .onChange(of: provider) { _, _ in page = 0 }
        .onChange(of: windows.map(\.id)) { _, _ in page = 0 }
    }

    @ViewBuilder private var quotaDetails: some View {
        if !windows.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(windows[QuotaWindowPages.range(windows: windows.count, page: page)])) { window in
                    windowCard(window, stale: store.results[provider]?.failure != nil)
                        .frame(maxWidth: .infinity)
                }
            }
        } else if let result = store.results[provider] {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.failure?.message ?? "等待可用额度 · 不显示估算数据")
                    .foregroundStyle(.orange).font(.system(size: 11)).lineLimit(2)
                if result.failure == .notSignedIn || result.failure == .expired || result.failure == .credentialsUnavailable {
                    Text(provider.loginHint).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ProgressView("正在读取…").controlSize(.small)
        }
    }

    private func providerTile(_ item: QuotaProvider) -> some View {
        let result = store.results[item]
        let window = result?.snapshot?.windows.first
        return Button { store.selectedProvider = item } label: {
            HStack(spacing: 10) {
                QuotaRing(provider: item, percent: window?.remainingPercent, stale: result?.failure != nil, size: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 12, weight: .semibold))
                    if let window {
                        Text("\(window.title)剩余\(result?.failure != nil ? " · 旧" : "")")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    } else {
                        Text(result?.failure == nil ? "读取中" : "需查看状态")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Group {
                    if let window { Text("\(window.remainingPercent, specifier: "%.0f")%") }
                    else { Text("—") }
                }
                .font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
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
            QuotaRing(provider: provider, percent: window.remainingPercent, stale: stale, size: 28)
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
        .lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var pinnedTitle: String {
        guard let pin = store.pins.selected, let provider = pin.provider else { return "选择固定额度" }
        return "\(provider.title) · \(store.window(for: pin)?.title ?? "已固定窗口")"
    }

    /// A single fixed row: status, paging and controls never scroll.
    private var pinSettings: some View {
        HStack(spacing: 10) {
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
            if pageCount > 1 {
                HStack(spacing: 5) {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(page == 0).accessibilityLabel("上一页额度")
                    Text("\(min(page + 1, pageCount))/\(pageCount)").monospacedDigit()
                    Button { page = min(pageCount - 1, page + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(page >= pageCount - 1).accessibilityLabel("下一页额度")
                }
                .font(.system(size: 10)).fixedSize()
            }
            QuotaRefreshStamp(updated: store.results[provider]?.snapshot?.fetchedAt,
                              next: store.results[provider]?.nextAttempt,
                              error: store.results[provider]?.failure?.message)
                .fixedSize()
            Menu {
                Toggle("圆环显示数字", isOn: Binding(
                    get: { store.pins.showsNumbers },
                    set: { value in store.updatePins { $0.showsNumbers = value } }
                ))
                Text("环内数字为剩余百分比，省略 % 号以保持紧凑。")
                if let failure = store.results[provider]?.failure {
                    Divider()
                    Text(failure.message)
                }
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("显示设置与状态说明").accessibilityLabel("额度显示设置")
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
        .padding(.horizontal, 10).padding(.vertical, 8)
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
    private var iconSize: CGFloat { QuotaCompactMetrics.iconSize(height: height) }

    var body: some View {
        if let pin = store.pins.selected, let provider = pin.provider {
            HStack(spacing: QuotaCompactMetrics.spacing) {
                Button {
                    if showsMusic { onMusic() } else { onSelect(provider) }
                } label: {
                    Group {
                        if showsMusic { albumWithActivity }
                        else {
                            QuotaBrandMark(brand: provider.brand)
                                .frame(width: iconSize, height: iconSize)
                        }
                    }
                    .frame(width: iconSize, height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsMusic ? "打开音乐" : "\(provider.title) · 打开额度")
                .accessibilityLabel(showsMusic ? "打开音乐" : "打开\(provider.title)额度")

                Color.clear.frame(width: centerWidth, height: height)

                Button { onSelect(provider) } label: {
                    quotaIndicator(pin, provider: provider)
                        .frame(width: iconSize, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(provider.title) · \(store.window(for: pin)?.title ?? "等待额度") · \(reading(for: pin))")
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
            .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if useVisualizer {
                        AudioSpectrumView(isPlaying: $music.isPlaying)
                            .frame(width: 16, height: 14)
                            .scaleEffect(0.45)
                            .frame(width: 9, height: 7)
                    } else {
                        LottieAnimationContainer()
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 9, height: 7)
                .padding(1)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .clipped()
    }

    private func reading(for pin: QuotaPin) -> String {
        guard let window = store.window(for: pin) else { return "额度未知" }
        let stale = pin.provider.flatMap { store.results[$0]?.failure } != nil
        return "剩余 \(Int(window.remainingPercent.rounded()))%\(stale ? "，旧数据" : "")"
    }

    private func quotaIndicator(_ pin: QuotaPin, provider: QuotaProvider) -> some View {
        CompactQuotaGauge(brand: provider.brand,
                          percent: store.window(for: pin)?.remainingPercent,
                          stale: store.results[provider]?.failure != nil,
                          showsBrand: showsMusic, showsNumbers: store.pins.showsNumbers, size: iconSize)
    }
}
