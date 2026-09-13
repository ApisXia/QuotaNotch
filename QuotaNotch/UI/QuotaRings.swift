// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaProvider {
    var brand: QuotaBrand { self == .gemini ? .gemini : (self == .claude ? .claude : .codex) }
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
        VStack(spacing: 6) {
            if store.enabled && store.visibleProviders.isEmpty {
                Spacer(minLength: 0)
                Text("所有 AI 服务已暂停").font(.headline)
                Button("管理 AI 服务") { SettingsWindowController.shared.showWindow() }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            } else if store.enabled {
                HStack(spacing: 2) {
                    ForEach(store.visibleProviders) { item in providerTile(item) }
                    Spacer(minLength: 0)
                }
                .padding(2)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                quotaDetails
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                pinSettings
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Spacer(minLength: 0)
                HStack(spacing: 20) {
                    ForEach(store.visibleProviders) { provider in
                        QuotaRing(provider: provider, percent: nil)
                    }
                }
                Text("让额度留在刘海边上").font(.headline)
                Text("读取这台 Mac 的 Claude / Codex / Gemini CLI 登录状态，查看剩余额度。")
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
        if !store.providerEnabled(provider) {
            VStack(spacing: 6) {
                Text("此服务已暂停").font(.caption).foregroundStyle(.secondary)
                Button(QuotaText.format("启用 %@", provider.title)) { store.setProvider(provider, enabled: true) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        } else if !windows.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(windows[QuotaWindowPages.range(windows: windows.count, page: page)])) { window in
                    windowCard(window, stale: store.results[provider]?.failure != nil)
                        .frame(maxWidth: .infinity)
                }
            }
        } else if let result = store.results[provider] {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(result.failure?.message ?? "等待可用额度 · 不显示估算数据"))
                    .foregroundStyle(.orange).font(.system(size: 11)).lineLimit(2)
                if result.failure == .notSignedIn || result.failure == .expired || result.failure == .credentialsUnavailable {
                    Text(LocalizedStringKey(provider.loginHint)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ProgressView("正在读取…").controlSize(.small)
        }
    }

    private func providerTile(_ item: QuotaProvider) -> some View {
        QuotaProviderTab(title: item.title, brand: item.brand, selected: provider == item) {
            store.selectedProvider = item
        }
    }

    private func windowCard(_ window: QuotaWindow, stale: Bool) -> some View {
        let pin = QuotaPin(providerID: provider.rawValue, windowID: window.id)
        let pinned = store.pins.selected == pin
        return QuotaWindowTile(title: window.localizedTitle,
                               percent: window.remainingPercent, reset: window.resetsAt,
                               accent: provider.accent, stale: stale, pinned: pinned) {
            store.updatePins { $0.selected = pinned ? nil : pin }
        }
    }

    private var pinnedTitle: String {
        guard let pin = store.pins.selected, let provider = pin.provider else { return QuotaText.localized("选择固定额度") }
        return "\(provider.title) · \(store.window(for: pin)?.localizedTitle ?? QuotaText.localized("已固定窗口"))"
    }

    /// A single fixed row: status, paging and controls never scroll.
    private var pinSettings: some View {
        HStack(spacing: 10) {
            Menu {
                Button("不固定") { store.updatePins { $0.selected = nil } }
                Divider()
                ForEach(store.visibleProviders) { item in
                    Section(item.title) {
                        ForEach(store.results[item]?.snapshot?.windows ?? []) { window in
                            let pin = QuotaPin(providerID: item.rawValue, windowID: window.id)
                            Button {
                                store.updatePins { $0.selected = pin }
                            } label: {
                                if store.pins.selected == pin {
                                    Label(window.localizedTitle, systemImage: "checkmark")
                                } else { Text(window.localizedTitle) }
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
        .padding(.horizontal, 10).padding(.vertical, 6)
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
                .help(showsMusic ? QuotaText.localized("打开音乐") : QuotaText.format("打开 %@ 额度", provider.title))
                .accessibilityLabel(showsMusic ? QuotaText.localized("打开音乐") : QuotaText.format("打开 %@ 额度", provider.title))

                Color.clear.frame(width: centerWidth, height: height)

                Button { onSelect(provider) } label: {
                    quotaIndicator(pin, provider: provider)
                        .frame(width: iconSize, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(provider.title) · \(store.window(for: pin)?.localizedTitle ?? QuotaText.localized("等待额度")) · \(reading(for: pin))")
                .accessibilityLabel("\(provider.title) \(store.window(for: pin)?.localizedTitle ?? QuotaText.localized("额度"))")
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
        guard let window = store.window(for: pin) else { return QuotaText.localized("额度未知") }
        let stale = pin.provider.flatMap { store.results[$0]?.failure } != nil
        return QuotaText.format("剩余 %d%%", Int(window.remainingPercent.rounded())) + (stale ? " · " + QuotaText.localized("旧数据") : "")
    }

    private func quotaIndicator(_ pin: QuotaPin, provider: QuotaProvider) -> some View {
        CompactQuotaGauge(brand: provider.brand,
                          percent: store.window(for: pin)?.remainingPercent,
                          stale: store.results[provider]?.failure != nil,
                          showsBrand: showsMusic, showsNumbers: store.pins.showsNumbers, size: iconSize)
    }
}
