// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension QuotaProvider {
    var brand: QuotaBrand { self == .claude ? .claude : .codex }
    var accent: Color { brand.color }
}

@MainActor
struct QuotaNotchView: View {
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var claude = ClaudeConnection.shared
    @AppStorage(NotchUISize.defaultsKey) private var sizeRaw = NotchUISize.current.rawValue
    @AppStorage(QuotaPetKind.defaultsKey) private var petRaw = QuotaPetKind.defaultKind.rawValue
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
                Picker("宠物", selection: Binding(get: { QuotaPetKind.choice(petRaw).rawValue }, set: { petRaw = $0 })) {
                    Text("麻薯 · 猫").tag(QuotaPetKind.mochi.rawValue)
                    Text("比特 · 机器人").tag(QuotaPetKind.bit.rawValue)
                    Text("果冻 · 史莱姆").tag(QuotaPetKind.jelly.rawValue)
                    Text("飘飘 · 小幽灵").tag(QuotaPetKind.ghost.rawValue)
                    Text("苗苗 · 豆芽").tag(QuotaPetKind.sprout.rawValue)
                }
                Picker("大小", selection: $sizeRaw) {
                    Text("小").tag(NotchUISize.small.rawValue)
                    Text("标准").tag(NotchUISize.standard.rawValue)
                    Text("大").tag(NotchUISize.large.rawValue)
                }
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

/// The closed notch: the quota pet with its numbers, or with the album while music plays.
/// Tasks show beside the pet and never swap modules, so the notch width stays put.
@MainActor
struct QuotaPinnedWings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var store = QuotaNotchStore.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var activity = AgentActivityStore.shared
    let centerWidth: CGFloat
    let height: CGFloat
    let showsMusic: Bool
    let albumArtNamespace: Namespace.ID
    let onSelect: (QuotaProvider) -> Void
    let onMusic: () -> Void
    @AppStorage(NotchUISize.defaultsKey) private var sizeRaw = NotchUISize.current.rawValue
    @AppStorage(QuotaPetKind.defaultsKey) private var petRaw = QuotaPetKind.defaultKind.rawValue
    @AppStorage(QuotaPetTint.defaultsKey) private var tintRaw = QuotaPetTint.original.rawValue
    private var size: NotchUISize { NotchUISize.stored(sizeRaw, legacyComfortable: false) }
    private var iconSize: CGFloat { QuotaCompactMetrics.iconSize(height: height, size: size) }
    private var pet: QuotaPetKind { QuotaPetKind.choice(petRaw) }
    private var petScale: CGFloat {
        QuotaPetArt.pixelScale(size: size, notchHeight: height, displayScale: displayScale)
    }
    /// Width of the pet at its pixel scale.
    private var quotaWidth: CGFloat { petScale > 1 ? 20 * petScale : iconSize }
    /// The percentage cell also carries the quota bar and up to three task dots.
    private var percentWidth: CGFloat { max(iconSize, (size.percentFont * 3).rounded()) }
    /// Both wings take the same slot so the camera stays centered, and the slot doesn't
    /// change when music starts or stops, so the notch keeps its width.
    private var slot: CGFloat { max(quotaWidth, percentWidth) }
    /// Tasks are shown only while task tracking is on and something is visible.
    private var taskStates: [AgentRunState] { activity.showAccessory ? activity.attention.states : [] }
    private var petTasks: QuotaPetTasks { QuotaPetTasks(activity.attention, enabled: activity.enabled) }
    /// While tasks show beside the pet, tapping it opens them.
    private var opensTasks: Bool { activity.showAccessory }

    var body: some View {
        if let pin = store.activePin, let provider = pin.provider {
            HStack(spacing: QuotaCompactMetrics.spacing) {
                Button {
                    if showsMusic { onMusic() }
                    else if opensTasks { openTasks() }
                    else { onSelect(provider) }
                } label: {
                    Group {
                        if showsMusic { album }
                        else { petView(pin, provider: provider) }
                    }
                    .frame(width: slot, height: height, alignment: showsMusic ? .trailing : .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showsMusic ? QuotaText.localized("打开音乐") : "\(provider.title) · \(reading(for: pin))")
                .accessibilityLabel(showsMusic ? QuotaText.localized("打开音乐") : QuotaText.format("打开 %@ 额度", provider.title))

                Color.clear.frame(width: centerWidth, height: height).auditNotchFrame("camera")

                Button {
                    if opensTasks { openTasks() } else { onSelect(provider) }
                } label: {
                    Group {
                        if showsMusic {
                            petView(pin, provider: provider)
                                .overlay(alignment: .bottomTrailing) {
                                    if !taskStates.isEmpty {
                                        QuotaPetTaskBadge(states: taskStates)
                                            .auditNotchModule("tasks", mode: "badge")
                                    }
                                }
                        } else {
                            QuotaPetSummary(percent: store.window(for: pin)?.remainingPercent, stale: store.isStale(provider),
                                            kind: pet, provider: provider, tint: QuotaPetTint(rawValue: tintRaw) ?? .original,
                                            fontSize: size.percentFont, tasks: taskStates)
                                .auditNotchModule("summary")
                        }
                    }
                    .frame(width: slot, height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(provider.title) · \(reading(for: pin))")
                .accessibilityLabel("\(provider.title) \(store.window(for: pin)?.localizedTitle ?? QuotaText.localized("额度"))")
                .accessibilityValue(reading(for: pin))
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: showsMusic)
        }
    }

    private func openTasks() {
        activity.notchReadEnabled = true
        BoringViewCoordinator.shared.currentView = .activity
        // The hosting notch commits its open state through the action below.
        NotificationCenter.default.post(name: .agentOpenNotch, object: nil)
    }

    private func petView(_ pin: QuotaPin, provider: QuotaProvider) -> some View {
        // Very short notches use the 16pt head-only sprite.
        QuotaPetView(kind: pet, size: iconSize >= 18 || petScale > 1 ? .widget : .minimal, provider: provider,
                     window: store.window(for: pin), stale: store.isStale(provider), scale: petScale, tasks: petTasks)
            .frame(width: quotaWidth, height: max(iconSize, 16 * petScale))
            .auditNotchModule("quota")
    }

    private var album: some View {
        Image(nsImage: music.albumArt)
            .resizable().scaledToFill()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .auditNotchModule("music").auditNotchFrame("album")
            .overlay(alignment: .bottomTrailing) {
                AudioSpectrumView(isPlaying: $music.isPlaying)
                    .frame(width: 16, height: 14)
                    .scaleEffect(0.45)
                    .frame(width: 9, height: 7)
                    .foregroundStyle(.white)
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
}
