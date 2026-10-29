// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum NotchEventPlacement: Sendable { case accessory, replacement }

/// Every new event must explicitly choose whether it supplements or replaces the primary row.
enum SneakContentType: CaseIterable, Sendable {
    case brightness, volume, backlight, music, mic

    var placement: NotchEventPlacement {
        switch self {
        case .brightness, .volume, .backlight, .music, .mic: return .accessory
        }
    }

    var isSystemControl: Bool {
        switch self {
        case .brightness, .volume, .backlight, .mic: return true
        case .music: return false
        }
    }
}

struct NotchEventPresentation {
    let expanded: SneakContentType?
    let notification: SneakContentType?

    var replacesPrimary: Bool {
        expanded?.placement == .replacement || notification?.placement == .replacement
    }

    var accessory: SneakContentType? {
        guard let notification, notification.placement == .accessory else { return nil }
        return notification
    }
}
