// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum QuotaText {
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
