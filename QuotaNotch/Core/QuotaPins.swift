// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct QuotaPin: Codable, Equatable, Sendable {
    let providerID: String
    let windowID: String
    var provider: QuotaProvider? { QuotaProvider(rawValue: providerID) }
}

struct QuotaPins: Codable, Equatable, Sendable {
    var left: QuotaPin?
    var right: QuotaPin?
    var yieldToMusic = true
    var hasPins: Bool { left?.provider != nil || right?.provider != nil }

    mutating func assign(_ pin: QuotaPin, toLeft: Bool) {
        // Moving a window never leaves the same window on both sides.
        if left == pin { left = nil }
        if right == pin { right = nil }
        if toLeft { left = pin } else { right = pin }
    }

    mutating func remove(_ pin: QuotaPin) {
        if left == pin { left = nil }
        if right == pin { right = nil }
    }

    func shouldDisplay(enabled: Bool, hidden: Bool, transient: Bool, musicPlaying: Bool) -> Bool {
        enabled && hasPins && !hidden && !transient && !(yieldToMusic && musicPlaying)
    }
}
