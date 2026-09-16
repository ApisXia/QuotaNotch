// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum NotchEventPlacement: Sendable { case accessory, replacement }

/// Every new event must explicitly choose whether it supplements or replaces the primary row.
enum SneakContentType: CaseIterable, Sendable {
    case brightness, volume, backlight, music, mic, battery, download

    var placement: NotchEventPlacement {
        switch self {
        case .brightness, .volume, .backlight, .music, .mic: return .accessory
        case .battery, .download: return .replacement
        }
    }

    var isSystemControl: Bool {
        switch self {
        case .brightness, .volume, .backlight, .mic: return true
        case .music, .battery, .download: return false
        }
    }
}

struct NotchEventPresentation {
    let expanded: SneakContentType?
    let notification: SneakContentType?
    var greeting = false

    var replacesPrimary: Bool {
        greeting || expanded?.placement == .replacement || notification?.placement == .replacement
    }

    var accessory: SneakContentType? {
        guard !greeting, let notification, notification.placement == .accessory else { return nil }
        return notification
    }
}
