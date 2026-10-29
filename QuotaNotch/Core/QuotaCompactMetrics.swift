// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The size setting for everything QuotaNotch draws in and under the notch.
/// `standard` keeps the original sizes (only the quota pet is enlarged); `small` and `large`
/// also scale the closed icons and the opened panel.
enum NotchUISize: String, CaseIterable, Sendable {
    case small, standard, large
    static let defaultsKey = "notchUISize"
    /// Users of the former "Larger display" toggle start at `large`.
    static func stored(_ raw: String?, legacyComfortable: Bool) -> NotchUISize {
        raw.flatMap(NotchUISize.init(rawValue:)) ?? (legacyComfortable ? .large : .standard)
    }
    static var current: NotchUISize {
        stored(UserDefaults.standard.string(forKey: defaultsKey),
               legacyComfortable: UserDefaults.standard.bool(forKey: "quotaComfortable"))
    }
    /// Scale of the opened panel and its contents.
    var panelScale: CGFloat {
        switch self { case .small: return 0.92; case .standard: return 1; case .large: return 1.12 }
    }
    static let largestPanelScale: CGFloat = 1.12
    /// Space kept around closed-notch icons, from the notch height.
    var iconInset: CGFloat {
        switch self { case .small: return 14; case .standard: return 12; case .large: return 10 }
    }
    /// Font size of the closed-notch percentage.
    var percentFont: CGFloat {
        switch self { case .small: return 11; case .standard: return 12; case .large: return 13 }
    }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 1 }
}

enum QuotaCompactMetrics {
    static let spacing: CGFloat = 8
    static func iconSize(height: CGFloat, size: NotchUISize) -> CGFloat {
        max(0, height - size.iconInset)
    }
    static func iconSize(height: CGFloat, comfortable: Bool = false) -> CGFloat {
        iconSize(height: height, size: comfortable ? .large : .standard)
    }
    static func chinAddition(height: CGFloat, comfortable: Bool = false) -> CGFloat {
        2 * iconSize(height: height, comfortable: comfortable) + 20
    }
}
