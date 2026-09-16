// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum QuotaText {
    static func percent(_ value: Double) -> String {
        if value > 0 && value < 1 { return "<1" }
        if value < 100 && value > 99 { return "99" }
        return String(format: "%.0f", min(100, max(0, value)))
    }
    static func countdown(_ reset: Date, now: Date) -> String {
        guard reset > now else { return localized("等待重置确认") }
        let minutes = max(1, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return format("%d 天 %d 小时后重置", minutes / 1440, (minutes % 1440) / 60) }
        if minutes >= 60 { return format("%d 小时 %d 分后重置", minutes / 60, minutes % 60) }
        return format("%d 分后重置", minutes)
    }
    static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: Locale.current, arguments: arguments)
    }
}

enum QuotaLanguage: String, CaseIterable {
    case system, english = "en", chinese = "zh-Hans"
    static let atLaunch = stored()
    static var locale: Locale {
        atLaunch == .system ? .autoupdatingCurrent : Locale(identifier: atLaunch.rawValue)
    }
    var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .chinese: return ["zh-Hans"]
        }
    }
    static func stored(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "quotaNotchLanguage") ?? "") ?? .system
    }
    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "quotaNotchLanguage")
        if let languages = appleLanguages { defaults.set(languages, forKey: "AppleLanguages") }
        else { defaults.removeObject(forKey: "AppleLanguages") }
    }
}

enum QuotaProviderVisibility {
    static func visible(disabled: Set<String>) -> [QuotaProvider] {
        QuotaProvider.allCases.filter { !disabled.contains($0.rawValue) }
    }
    static func selection(_ current: QuotaProvider, disabled: Set<String>) -> QuotaProvider? {
        let providers = visible(disabled: disabled)
        return providers.contains(current) ? current : providers.first
    }
}
