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

    /// Every window QuotaNotch currently has a reading for, across enabled services.
    var availablePins: [QuotaPin] {
        visibleProviders.flatMap { provider in
            (results[provider]?.snapshot?.windows ?? []).map { QuotaPin(providerID: provider.rawValue, windowID: $0.id) }
        }
    }
    var automaticPin: QuotaPin? {
        guard enabled && pins.automatic else { return nil }
        return QuotaAutomaticSelection.select(candidates: availablePins, results: results, now: now)
    }

    /// What the closed notch shows: the lowest fresh window, nothing, or one fixed window.
    enum NotchChoice: Hashable { case automatic, none, fixed(QuotaPin) }
    var notchChoice: NotchChoice {
        get {
            if pins.automatic { return .automatic }
            return pins.selected.map { .fixed($0) } ?? .none
        }
        set {
            updatePins { pins in
                switch newValue {
                case .automatic: pins.automatic = true
                case .none: pins.automatic = false; pins.selected = nil
                case .fixed(let pin): pins.automatic = false; pins.selected = pin
                }
            }
        }
    }
    func title(for pin: QuotaPin) -> String {
        let window = window(for: pin)?.localizedTitle ?? QuotaText.localized([
            "five_hour": "5 小时", "seven_day": "7 天", "primary_window": "主窗口", "secondary_window": "次窗口"
        ][pin.windowID] ?? pin.windowID)
        return (pin.provider?.title ?? pin.providerID) + " · " + window
    }
    var notchChoiceTitle: String {
        switch notchChoice {
        case .automatic:
            return QuotaText.localized("自动") + (activePin.map { " · " + title(for: $0) } ?? "")
        case .none: return QuotaText.localized("不显示")
        case .fixed(let pin): return title(for: pin)
        }
    }
    var activePin: QuotaPin? {
        automaticPin ?? pins.selected.flatMap { pin in
            pin.provider.map { providerEnabled($0) } == true ? pin : nil
        }
    }
    var presentationPins: QuotaPins { QuotaPins(selected: activePin, showsNumbers: pins.showsNumbers) }
    func isStale(_ provider: QuotaProvider) -> Bool { results[provider]?.isStale(provider: provider, now: now) ?? true }

    @Published private(set) var requestingNotifications = false
    @Published private(set) var notificationsDenied = false

    func refreshNotificationStatus() async {
        #if SETTINGS_PREVIEW
        return
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
        if notificationsDenied {
            notificationStatus = QuotaText.localized("请在系统设置中允许通知")
        } else if UserDefaults.standard.bool(forKey: "quotaNotifications") {
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            notificationStatus = QuotaText.localized(allowed ? "通知已启用" : "请在系统设置中允许通知")
        } else {
            notificationStatus = QuotaText.localized("Notifications are off. Your threshold is saved.")
        }
    }

    func setNotifications(_ enabled: Bool) async {
        guard !requestingNotifications else { return }
        if !enabled {
            UserDefaults.standard.set(false, forKey: "quotaNotifications")
            await refreshNotificationStatus()
            return
        }
        requestingNotifications = true
        defer { requestingNotifications = false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(granted, forKey: "quotaNotifications")
            notificationStatus = QuotaText.localized(granted ? "通知已启用" : "请在系统设置中允许通知")
            await refreshNotificationStatus()
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
    /// Recent changes per window, so the quota pet can react to them.
    @Published private(set) var petTracker = QuotaPetTracker()
    @Published private(set) var refreshing = false
    /// A short line shown below the notch for a few seconds at key quota moments.
    @Published private(set) var peek: String?
    private var peekBaseline: (key: String, remaining: Double, pacing: Bool)?
    private var peekClear: Task<Void, Never>?
    /// Quota is always on; individual services can be turned off. Claude only reads a local
    /// file now, so there is no cost to monitoring by default. (Kept for the preview runner.)
    @Published private(set) var enabled = true
    @Published var selectedProvider: QuotaProvider = .claude
    @Published private(set) var pins: QuotaPins = {
        guard let data = UserDefaults.standard.data(forKey: "quotaNotchPins"),
              let value = try? JSONDecoder().decode(QuotaPins.self, from: data) else { return QuotaPins() }
        return value
    }()
    @Published private var disabledProviders = Set(UserDefaults.standard.stringArray(forKey: "quotaNotchDisabledProviders") ?? [])

    var visibleProviders: [QuotaProvider] { QuotaProviderVisibility.visible(disabled: disabledProviders) }

    func providerEnabled(_ provider: QuotaProvider) -> Bool { !disabledProviders.contains(provider.rawValue) }

    func setProvider(_ provider: QuotaProvider, enabled: Bool) {
        generation += 1
        if enabled { disabledProviders.remove(provider.rawValue) }
        else {
            disabledProviders.insert(provider.rawValue)
            results[provider] = nil
        }
        if let selection = QuotaProviderVisibility.selection(selectedProvider, disabled: disabledProviders) {
            selectedProvider = selection
        }
        UserDefaults.standard.set(Array(disabledProviders), forKey: "quotaNotchDisabledProviders")
        if enabled { Task { await refresh() } }
    }


    #if SETTINGS_PREVIEW
    func configureSettingsPreview(paused: Bool) {
        enabled = !paused
        disabledProviders = []
        let pin = QuotaPin(providerID: "claude", windowID: "five_hour")
        pins = QuotaPins(selected: pin)
        pins.automatic = true
        pins.candidates = [pin, QuotaPin(providerID: "codex", windowID: "primary_window")]
        let window = QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: 42, resetsAt: nil)
        results = paused ? [:] : [.claude: QuotaResult(snapshot: QuotaSnapshot(windows: [window], fetchedAt: now), failure: nil, nextAttempt: now)]
        notificationStatus = QuotaText.localized("Notifications are off. Your threshold is saved.")
    }

    func setPreviewPeek(_ text: String?) { peekClear?.cancel(); peek = text }
    #endif

    private let client = QuotaClient(claudeFallback: ClaudeCLIQuotaFallback())
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
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { break }
            }
        }
    }

    func refresh(providerOnly: QuotaProvider? = nil, manual: Bool = false) async {
        #if SETTINGS_PREVIEW
        return // This executable only renders fixture data, even if an action requests a refresh.
        #endif
        guard enabled, !inProgress else { return }
        let requestGeneration = generation
        let current = Date()
        if manual || current.timeIntervalSince(now) >= 30 { now = current }
        let providers = QuotaProvider.allCases.filter {
            providerEnabled($0) && (providerOnly == nil || providerOnly == $0)
                && canRefresh($0, at: current, manual: manual)
        }
        guard !providers.isEmpty else { return }
        // Only a user-initiated refresh shows progress; background polls stay invisible.
        inProgress = true
        if manual { refreshing = true }
        defer { inProgress = false; if refreshing { refreshing = false } }
        // When a Claude session last changed (terminal or VS Code), so the quota follows it.
        let claudeActivity = AgentActivityStore.shared.sessions.filter { $0.provider == .claude }.map(\.updatedAt).max()
        await withTaskGroup(of: (QuotaProvider, QuotaResult).self) { group in
            for provider in providers {
                group.addTask { [client] in
                    (provider, await client.refresh(provider, manual: manual, claudeActivity: claudeActivity))
                }
            }
            for await (provider, result) in group {
                guard enabled, generation == requestGeneration, !Task.isCancelled, providerEnabled(provider) else { continue }
                notify(result, provider: provider)
                if results[provider] != result {
                    if let snapshot = result.snapshot { petTracker.observe(snapshot, provider: provider) }
                    results[provider] = result
                }
            }
        }
        updatePeek(at: current)
    }

    /// Compares the shown window with its last reading and raises a peek on a key moment.
    private func updatePeek(at date: Date) {
        guard let pin = activePin, let provider = pin.provider, let window = window(for: pin) else { return }
        let key = QuotaPetTracker.key(provider: provider, windowID: window.id)
        let pacing = QuotaPace.runsOutBeforeReset(window, now: date)
        let previous = peekBaseline?.key == key ? peekBaseline : nil
        peekBaseline = (key, window.remainingPercent, pacing)
        guard !isStale(provider), QuotaPeekRule.event(previous: previous?.remaining, current: window.remainingPercent,
                                                      wasPacing: previous?.pacing ?? false, pacing: pacing) != nil else { return }
        showPeek(Self.peekText(provider: provider, window: window, now: date))
    }

    static func peekText(provider: QuotaProvider, window: QuotaWindow, now: Date) -> String {
        var parts = [provider.title + " " + window.localizedTitle,
                     QuotaText.localized("剩余") + " " + QuotaText.percent(window.remainingPercent) + "%"]
        if let reset = window.resetsAt { parts.append(QuotaText.countdown(reset, now: now)) }
        return parts.joined(separator: " · ")
    }

    private func showPeek(_ text: String?) {
        peekClear?.cancel()
        peek = text
        guard text != nil else { return }
        peekClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(QuotaPeekRule.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.peek = nil
        }
    }

    private var inProgress = false

    /// Manual Claude refreshes may skip the cooldown when nothing recent is shown (see QuotaClient).
    func canRefresh(_ provider: QuotaProvider, at date: Date, manual: Bool) -> Bool {
        guard let result = results[provider] else { return true }
        return result.nextAttempt <= date
            || QuotaClient.mayBypassCooldown(provider: provider, manual: manual, result: result, now: date)
    }
}
