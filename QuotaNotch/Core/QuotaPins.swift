// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct QuotaPin: Codable, Equatable, Sendable {
    let providerID: String
    let windowID: String
    var provider: QuotaProvider? { QuotaProvider(rawValue: providerID) }
}

struct QuotaPins: Codable, Equatable, Sendable {
    var selected: QuotaPin?
    var showsNumbers = false
    var hasPins: Bool { selected?.provider != nil }

    init(selected: QuotaPin? = nil, showsNumbers: Bool = false) {
        self.selected = selected
        self.showsNumbers = showsNumbers
    }

    private enum CodingKeys: String, CodingKey { case selected, left, right, showsNumbers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showsNumbers = try values.decodeIfPresent(Bool.self, forKey: .showsNumbers) ?? false
        if values.contains(.selected) {
            selected = try values.decodeIfPresent(QuotaPin.self, forKey: .selected)
        } else {
            // Preserve one existing choice during upgrade: right, then left.
            let right = try values.decodeIfPresent(QuotaPin.self, forKey: .right)
            let left = try values.decodeIfPresent(QuotaPin.self, forKey: .left)
            selected = right?.provider != nil ? right : left
        }
        if selected?.provider == nil { selected = nil }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(selected, forKey: .selected)
        try values.encode(showsNumbers, forKey: .showsNumbers)
    }

    func presentation(enabled: Bool, hidden: Bool, transient: Bool, musicPlaying: Bool) -> QuotaPresentation {
        guard !hidden && !transient else { return .none }
        switch (enabled && hasPins, musicPlaying) {
        case (true, true): return .combined
        case (true, false): return .quota
        case (false, true): return .music
        case (false, false): return .none
        }
    }
}

enum QuotaPresentation: Equatable { case none, music, quota, combined }

/// Resolve only at the moment a closed notch opens. Open content never follows the pointer.
enum QuotaOpeningPage: Equatable { case home, quota }
extension QuotaPresentation {
    func openingPage(pointerX: Double, midpointX: Double, isOpen: Bool) -> QuotaOpeningPage? {
        guard !isOpen else { return nil }
        switch self {
        case .none: return nil
        case .music: return .home
        case .quota: return .quota
        case .combined: return pointerX < midpointX ? .home : .quota
        }
    }
}
