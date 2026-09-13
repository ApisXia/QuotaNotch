// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
final class QuotaNotchStore: ObservableObject {
    static let shared = QuotaNotchStore()
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
        let providers = QuotaProvider.allCases.filter { providerEnabled($0) }
        await withTaskGroup(of: (QuotaProvider, QuotaResult).self) { group in
            for provider in providers {
                group.addTask { [client] in (provider, await client.refresh(provider)) }
            }
            for await (provider, result) in group {
                guard enabled, !Task.isCancelled, providerEnabled(provider) else { continue }
                results[provider] = result
            }
        }
    }
}
