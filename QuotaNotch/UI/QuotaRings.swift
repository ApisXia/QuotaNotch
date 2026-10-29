// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaProvider {
    var brand: QuotaBrand { self == .claude ? .claude : .codex }
    var accent: Color { brand.color }
}

/// A missing reading is an empty track and a dash, never a full or zero quota claim.
struct QuotaRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let provider: QuotaProvider
    let percent: Double?
    var stale = false
    var size: CGFloat = 42

    var body: some View {
        let ink = QuotaWarningInk(accent: provider.accent, percent: percent, stale: stale)
        ZStack {
            Circle().stroke(ink.track, lineWidth: size > 30 ? 3 : 2)
                .shadow(color: ink.warning.exhausted ? ink.halo : .clear, radius: 1.5)
            if let percent {
                Circle().trim(from: 0, to: ink.warning.fraction)
                    .stroke(ink.color,
                            style: StrokeStyle(lineWidth: size > 30 ? 3 : 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ink.halo, radius: 1.5)
            }
            QuotaBrandMark(brand: provider.brand, muted: stale)
                .frame(width: size * 0.48, height: size * 0.48)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: percent)
        .accessibilityHidden(true)
    }
}

@MainActor
struct QuotaNotchView: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var claude = ClaudeConnection.shared
    @AppStorage("quotaComfortable") private var comfortable = false
    private var provider: QuotaProvider { store.selectedProvider }

    var body: some View {
        VStack(spacing: 6) {
            if store.visibleProviders.isEmpty {
                Spacer(minLength: 0)
                Text("所有 AI 服务已关闭").font(.headline)
                Button("管理 AI 服务") { openSettings("Quota") }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            } else {
                // One service per tab, as before; the tab row stays the familiar switcher.
                HStack(spacing: 2) {
                    ForEach(store.visibleProviders) { item in
                        QuotaProviderTab(title: item.title, brand: item.brand, selected: provider == item) {
                            store.selectedProvider = item
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(2)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                providerRow(provider)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                footer.fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .task { store.start(); claude.check() }
    }

    /// Both windows of one service, or one card that says what is missing and how to fix it.
    @ViewBuilder private func providerRow(_ provider: QuotaProvider) -> some View {
        let windows = Array((store.results[provider]?.snapshot?.windows ?? []).prefix(2))
        if !store.providerEnabled(provider) {
            VStack(spacing: 6) {
                Text("此服务已暂停").font(.caption).foregroundStyle(.secondary)
                Button(QuotaText.format("启用 %@", provider.title)) { store.setProvider(provider, enabled: true) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        } else if !windows.isEmpty {
            HStack(spacing: 8) {
                ForEach(windows) { window in windowCard(window, provider: provider).frame(maxWidth: .infinity) }
            }
        } else {
            HStack(spacing: 8) {
                QuotaBrandMark(brand: provider.brand).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.title).font(.system(size: 11, weight: .medium))
                    Text(emptyMessage(provider)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 6)
                if provider == .claude && !claude.installed {
                    Button("连接 Claude Code") { claude.setConnected(true) }
                        .buttonStyle(.borderedProminent).controlSize(.small).disabled(claude.busy)
                } else if store.results[provider] == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func emptyMessage(_ provider: QuotaProvider) -> String {
        if provider == .claude {
            if !claude.installed { return QuotaText.localized("连接后显示 5 小时和 7 天额度") }
            if store.results[.claude]?.failure == .notConnected || store.results[.claude]?.failure == nil {
                return QuotaText.localized("在 Claude Code 中发送一条消息后显示")
            }
        }
        if let failure = store.results[provider]?.failure {
            return failure == .notSignedIn ? QuotaText.localized("在终端运行 codex login") : failure.message
        }
        return QuotaText.localized("正在读取…")
    }

    private func windowCard(_ window: QuotaWindow, provider: QuotaProvider) -> some View {
        let pin = QuotaPin(providerID: provider.rawValue, windowID: window.id)
        let pinned = store.activePin == pin
        return QuotaWindowTile(title: window.localizedTitle,
                               percent: window.remainingPercent, reset: window.resetsAt,
                               accent: provider.accent, stale: store.isStale(provider), pinned: pinned) {
            store.notchChoice = pinned && store.notchChoice != .automatic ? .none : .fixed(pin)
        }
    }

    private func openSettings(_ page: String) {
        UserDefaults.standard.set(page, forKey: "settingsSelectedTab")
        SettingsWindowController.shared.showWindow()
    }

    /// Display choice on the left; status, settings and refresh on the right.
    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("收起时显示", selection: Binding(get: { store.notchChoice }, set: { store.notchChoice = $0 })) {
                    Text("自动（剩余最少的额度）").tag(QuotaNotchStore.NotchChoice.automatic)
                    Text("不显示").tag(QuotaNotchStore.NotchChoice.none)
                    ForEach(store.availablePins, id: \.self) { pin in
                        Text(verbatim: store.title(for: pin)).tag(QuotaNotchStore.NotchChoice.fixed(pin))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(QuotaText.localized("收起时") + " · " + store.notchChoiceTitle, systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("收起刘海时显示哪个额度")
            if store.refreshing {
                Text("正在刷新…").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Menu {
                Toggle("圆环中显示剩余百分比", isOn: Binding(
                    get: { store.pins.showsNumbers },
                    set: { value in store.updatePins { $0.showsNumbers = value } }
                ))
                Toggle("大字模式", isOn: $comfortable)
                Divider()
                Button("AI 额度设置…") { openSettings("Quota") }
                Button("连接…") { openSettings("Connections") }
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("额度显示设置").accessibilityLabel("额度显示设置")
            TimelineView(.periodic(from: .now, by: 5)) { context in
                let refreshable = store.visibleProviders.contains { store.canRefresh($0, at: context.date, manual: true) }
                Button { Task { await store.refresh(manual: true) } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.refreshing || !refreshable)
                .help(updatedSummary)
            }
            .fixedSize()
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private var updatedSummary: String {
        store.visibleProviders.compactMap { provider in
            store.results[provider]?.snapshot.map { provider.title + " · " + QuotaText.localized("更新于") + " " + QuotaText.relative($0.fetchedAt) }
        }.joined(separator: "\n")
    }
}

/// One quota selection shares the cutout with music and temporary task activity.
@MainActor
struct QuotaPinnedWings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var activity = AgentActivityStore.shared
    let centerWidth: CGFloat
    let height: CGFloat
    let showsMusic: Bool
    let albumArtNamespace: Namespace.ID
    let onSelect: (QuotaProvider) -> Void
    let onMusic: () -> Void
    @AppStorage("quotaComfortable") private var comfortable = false
    private var iconSize: CGFloat { QuotaCompactMetrics.iconSize(height: height, comfortable: comfortable) }

    private var tasksExpanded: Bool { showsMusic && activity.compactExpanded && activity.showAccessory }
    private var metrics: NotchModuleMetrics { NotchModuleMetrics(widgetWidth: iconSize) }
    private var leftWidth: CGFloat { iconSize }
    private var rightPrimaryWidth: CGFloat {
        guard activity.showAccessory else { return iconSize }
        return showsMusic ? (tasksExpanded ? metrics.minimalWidth : iconSize) : 0
    }

    var body: some View {
        if let pin = store.activePin, let provider = pin.provider {
            HStack(spacing: QuotaCompactMetrics.spacing) {
                Button {
                    if showsMusic { onMusic() }
                    else { onSelect(provider) }
                } label: {
                    Group {
                        if showsMusic { albumWithActivity }
                        else if activity.showAccessory { quotaIndicator(pin, provider: provider) }
                        else {
                            QuotaBrandMark(brand: provider.brand)
                                .frame(width: iconSize, height: iconSize)
                                .auditNotchModule("quota")
                        }
                    }
                    .frame(width: leftWidth, height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsMusic ? QuotaText.localized("打开音乐") : QuotaText.format("打开 %@ 额度", provider.title))
                .accessibilityLabel(showsMusic ? QuotaText.localized("打开音乐") : QuotaText.format("打开 %@ 额度", provider.title))

                .catWing(.left, occupied: leftWidth, height: height, widgetWidth: iconSize)
                Color.clear.frame(width: centerWidth, height: height).auditNotchFrame("camera")

                AgentCompactDock(primaryWidth: rightPrimaryWidth, height: height, anchorWidth: leftWidth, widgetWidth: iconSize, open: {
                    BoringViewCoordinator.shared.currentView = .activity
                    // The hosting notch commits its open state through the action below.
                    NotificationCenter.default.post(name: .agentOpenNotch, object: nil)
                }) {
                    if !activity.showAccessory || showsMusic {
                        Button {
                            onSelect(provider)
                        } label: {
                            Group {
                                if tasksExpanded { minimalQuota(pin, provider: provider) }
                                else { quotaIndicator(pin, provider: provider) }
                            }
                            .frame(width: rightPrimaryWidth, height: height)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(provider.title) · \(reading(for: pin))")
                        .accessibilityLabel("\(provider.title) \(store.window(for: pin)?.localizedTitle ?? QuotaText.localized("额度"))")
                        .accessibilityValue(reading(for: pin))
                    }
                }
                .catWing(.right, occupied: showsMusic && activity.showAccessory ? iconSize + metrics.additionalWidth : iconSize, height: height, widgetWidth: iconSize)
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: showsMusic)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: tasksExpanded)
        }
    }

    private func minimalQuota(_ pin: QuotaPin, provider: QuotaProvider) -> some View {
        NotchMinimalIcon(metrics: metrics) {
            MinimalQuotaGlyph(brand: provider.brand,
                              percent: store.window(for: pin)?.remainingPercent,
                              stale: store.isStale(provider), size: metrics.minimalIconSize)
        }
        .frame(width: metrics.minimalWidth, height: height)
        .auditNotchModule("quota", mode: "minimal")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.title + " · " + reading(for: pin))
    }

    private var albumWithActivity: some View {
        Image(nsImage: music.albumArt)
            .resizable().scaledToFill()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .auditNotchModule("music").auditNotchFrame("album")
            .overlay(alignment: .bottomTrailing) {
                Group {
                        AudioSpectrumView(isPlaying: $music.isPlaying)
                            .frame(width: 16, height: 14)
                            .scaleEffect(0.45)
                            .frame(width: 9, height: 7)
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
        let stale = pin.provider.map { store.isStale($0) } ?? true
        return QuotaText.localized("剩余") + " " + QuotaText.percent(window.remainingPercent) + "%" + (stale ? " · " + QuotaText.localized("旧数据") : "")
    }

    private func quotaIndicator(_ pin: QuotaPin, provider: QuotaProvider) -> some View {
        CompactQuotaGauge(brand: provider.brand,
                          percent: store.window(for: pin)?.remainingPercent,
                          stale: store.isStale(provider),
                          showsBrand: showsMusic || activity.showAccessory, showsNumbers: store.pins.showsNumbers, size: iconSize)
            .auditNotchModule("quota")
    }
}

/// A brand-centered quota symbol; the arc communicates remaining quota without numeric text.
struct MinimalQuotaGlyph: View {
    let brand: QuotaBrand
    let percent: Double?
    var stale = false
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let valid = percent?.isFinite == true
        let ink = QuotaWarningInk(accent: brand.color, percent: percent, stale: stale)
        let stroke: CGFloat = 1.1
        ZStack {
            Circle().inset(by: stroke / 2 + 0.25)
                .stroke(ink.track, style: StrokeStyle(lineWidth: stroke, dash: !valid || stale ? [1.3, 1.6] : []))
            if valid {
                Circle().inset(by: stroke / 2 + 0.25).trim(from: 0, to: ink.warning.fraction)
                    .stroke(ink.color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            QuotaBrandMark(brand: brand, muted: stale || !valid)
                .frame(width: size * 0.48, height: size * 0.48)
        }.frame(width: size, height: size)
        .animation(reduced ? nil : .easeInOut(duration: 0.3), value: percent)
        .accessibilityHidden(true)
    }
}
