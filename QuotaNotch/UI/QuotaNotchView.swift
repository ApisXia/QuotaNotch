// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UserNotifications
import Combine

@MainActor
final class QuotaNotchStore: ObservableObject {
    static let shared = QuotaNotchStore()
    @Published var menuOpen = false
    @Published var notificationStatus = ""
    @Published private(set) var now = Date()
    private var generation = 0
    private var menuObservers = Set<AnyCancellable>()
    private var wakeObserver: AnyCancellable?
    private var alertStates: [String: QuotaAlertState] = {
        guard let data = UserDefaults.standard.data(forKey: "quotaAlertStates") else { return [:] }
        return (try? JSONDecoder().decode([String: QuotaAlertState].self, from: data)) ?? [:]
    }()

    init() {
        // The oversized development build used a larger default. Return that build
        // to the compact presentation once, then respect subsequent user choices.
        if !UserDefaults.standard.bool(forKey: "quotaCompactRefinementApplied") {
            UserDefaults.standard.set(false, forKey: "quotaComfortable")
            UserDefaults.standard.set(true, forKey: "quotaCompactRefinementApplied")
        }
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.menuOpen = true }.store(in: &menuObservers)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.menuOpen = false }.store(in: &menuObservers)
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor in
                    self?.now = Date()
                    await self?.refresh()
                }
            }
    }

    var activePin: QuotaPin? {
        guard pins.automatic else { return pins.selected }
        return QuotaAutomaticSelection.select(candidates: pins.candidates.filter {
            $0.provider.map { providerEnabled($0) } ?? false
        }, results: results, now: now) ?? pins.selected
    }
    var presentationPins: QuotaPins { QuotaPins(selected: activePin, showsNumbers: pins.showsNumbers) }
    func isStale(_ provider: QuotaProvider) -> Bool { results[provider]?.isStale(provider: provider, now: now) ?? true }

    func setNotifications(_ enabled: Bool) async {
        if !enabled { UserDefaults.standard.set(false, forKey: "quotaNotifications"); return }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(granted, forKey: "quotaNotifications")
            notificationStatus = QuotaText.localized(granted ? "通知已启用" : "请在系统设置中允许通知")
        } catch { notificationStatus = QuotaText.localized("无法启用通知，请检查系统设置") }
    }

    private func notify(_ result: QuotaResult, provider: QuotaProvider) {
        guard UserDefaults.standard.bool(forKey: "quotaNotifications"), result.failure == nil,
              let snapshot = result.snapshot, snapshot.fetchedAt != results[provider]?.snapshot?.fetchedAt else { return }
        let stored = UserDefaults.standard.double(forKey: "quotaAlertThreshold")
        let threshold = stored > 0 ? stored : 20
        for window in snapshot.windows {
            let key = provider.rawValue + ":" + window.id
            var state = alertStates[key] ?? QuotaAlertState()
            for event in state.observe(window, threshold: threshold) {
                let content = UNMutableNotificationContent()
                content.title = provider.title + " · " + window.localizedTitle
                content.body = QuotaText.localized(event == .low ? "额度偏低" : "额度已恢复") + " · " + QuotaText.percent(window.remainingPercent) + "%"
                content.sound = .default
                let request = UNNotificationRequest(identifier: "quota-" + key + (event == .low ? "-low" : "-recovered"), content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
            alertStates[key] = state
        }
        if let data = try? JSONEncoder().encode(alertStates) { UserDefaults.standard.set(data, forKey: "quotaAlertStates") }
    }

    func copyDiagnostics() {
        var lines = ["QuotaNotch " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
                     "macOS " + ProcessInfo.processInfo.operatingSystemVersionString]
        for provider in QuotaProvider.allCases {
            let result = results[provider]
            lines.append(provider.title + ": " + (providerEnabled(provider) ? (result?.failure?.message ?? QuotaText.localized(result?.snapshot == nil ? "等待查询" : "已连接")) : QuotaText.localized("此服务已暂停")))
            if let date = result?.snapshot?.fetchedAt { lines.append("Updated: " + date.ISO8601Format()) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @Published private(set) var results: [QuotaProvider: QuotaResult] = [:]
    @Published private(set) var refreshing = false
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "quotaNotchEnabled")
    @Published var selectedProvider: QuotaProvider = .claude
    @Published private(set) var pins: QuotaPins = {
        guard let data = UserDefaults.standard.data(forKey: "quotaNotchPins"),
              let value = try? JSONDecoder().decode(QuotaPins.self, from: data) else { return QuotaPins() }
        return value
    }()
    @Published private var disabledProviders = Set(UserDefaults.standard.stringArray(forKey: "quotaNotchDisabledProviders") ?? ["gemini"])

    var visibleProviders: [QuotaProvider] { QuotaProviderVisibility.visible(disabled: disabledProviders) }

    func providerEnabled(_ provider: QuotaProvider) -> Bool { !disabledProviders.contains(provider.rawValue) }

    func setProvider(_ provider: QuotaProvider, enabled: Bool) {
        generation += 1
        if enabled { disabledProviders.remove(provider.rawValue) }
        else {
            disabledProviders.insert(provider.rawValue)
            results[provider] = nil
            if pins.selected?.provider == provider { updatePins { $0.selected = nil } }
        }
        if let selection = QuotaProviderVisibility.selection(selectedProvider, disabled: disabledProviders) {
            selectedProvider = selection
        }
        UserDefaults.standard.set(Array(disabledProviders), forKey: "quotaNotchDisabledProviders")
        if enabled { Task { await refresh() } }
    }

    private let client = QuotaClient()
    private var polling: Task<Void, Never>?

    func updatePins(_ change: (inout QuotaPins) -> Void) {
        var value = pins
        change(&value)
        pins = value
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "quotaNotchPins")
        }
    }

    func window(for pin: QuotaPin) -> QuotaWindow? {
        guard let provider = pin.provider else { return nil }
        return results[provider]?.snapshot?.windows.first { $0.id == pin.windowID }
    }

    func setEnabled(_ value: Bool) {
        generation += 1
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
        if let selection = QuotaProviderVisibility.selection(selectedProvider, disabled: disabledProviders) {
            selectedProvider = selection
        }
        guard enabled, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { break }
            }
        }
    }

    func refresh(providerOnly: QuotaProvider? = nil) async {
        guard enabled, !refreshing else { return }
        let requestGeneration = generation
        now = Date()
        let providers = QuotaProvider.allCases.filter {
            providerEnabled($0) && (providerOnly == nil || providerOnly == $0)
                && (results[$0]?.nextAttempt ?? .distantPast) <= now
        }
        guard !providers.isEmpty else { return }
        refreshing = true
        defer { refreshing = false }
        await withTaskGroup(of: (QuotaProvider, QuotaResult).self) { group in
            for provider in providers {
                group.addTask { [client] in (provider, await client.refresh(provider)) }
            }
            for await (provider, result) in group {
                guard enabled, generation == requestGeneration, !Task.isCancelled, providerEnabled(provider) else { continue }
                notify(result, provider: provider)
                results[provider] = result
            }
        }
    }
}
