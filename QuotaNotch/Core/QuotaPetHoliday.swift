// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Holiday outfits: on these days every pet wears a small hat, with a little moving extra beside it.
enum QuotaPetHoliday: String, CaseIterable, Sendable {
    case springFestival, midAutumn, halloween, christmas, birthday

    /// On by default; "off" turns outfits off.
    static let defaultsKey = "quotaPetHolidays"
    /// The user's birthday as "MM-dd", or empty.
    static let birthdayKey = "quotaPetBirthday"

    /// Hat colors, shared by every pet's palette (no pet uses digits).
    static let colors: [Character: UInt32] = [
        "1": 0xE8443A, "2": 0xFFD34D, "3": 0xFFFFFF, "4": 0xFFB3C8, "5": 0x3B2A5A, "6": 0xFF9A2A, "7": 0x7AA2FF
    ]

    /// The hat, bottom row is the brim.
    var hat: [String] {
        switch self {
        case .springFestival: return ["..111..", ".12221.", "1111111", ".22222."]
        case .midAutumn: return [".3...3.", "343.343", "343.343", ".33333."]
        case .halloween: return ["....5..", "...55..", "..555..", ".56665.", "5555555"]
        case .christmas: return ["....113", "..1111.", ".11111.", "3333333"]
        case .birthday: return ["...2...", "..727..", "..272..", ".72727."]
        }
    }

    /// The little moving extra beside the pet, in sprite pixels, at `time` seconds.
    func extras(at time: TimeInterval) -> [QuotaPetParticle] {
        switch self {
        case .springFestival:
            return [.init(kind: .lantern, x: 17 + (sin(time / 0.3)).rounded(), y: 6, opacity: 1)]
        case .midAutumn:
            return [.init(kind: .moon, x: 16, y: 7 + (sin(time / 0.5)).rounded(), opacity: 1)]
        case .halloween:
            return [.init(kind: Int(time / 0.2) % 2 == 1 ? .batUp : .batDown, x: 15 + (sin(time / 0.4) * 2).rounded(),
                          y: 6 + (cos(time / 0.3)).rounded(), opacity: 1),
                    .init(kind: .pumpkin, x: -1, y: 12, opacity: 1)]
        case .christmas:
            return (0..<5).map { k in
                let x = (Double(k) * 4.3 + 1).truncatingRemainder(dividingBy: 20)
                let y = (time / 0.12 + Double(k) * 3.7).truncatingRemainder(dividingBy: 18) - 2
                return .init(kind: .snow, x: x, y: y, opacity: 1)
            }
        case .birthday:
            let kinds: [QuotaPetParticle.Kind] = [.confettiPink, .confettiBlue, .confettiYellow, .confettiGreen]
            return (0..<6).map { k in
                let x = (Double(k) * 3.3 + 1.5).truncatingRemainder(dividingBy: 20)
                let y = (time / 0.15 + Double(k) * 2.9).truncatingRemainder(dividingBy: 18) - 2
                return .init(kind: kinds[k % 4], x: x, y: y, opacity: 1)
            }
        }
    }

    /// Today's holiday, if any: Lunar New Year's Eve to the 7th day, Mid-Autumn and the days either
    /// side, Oct 30 – Nov 1, Dec 24 – 26, and the birthday ("MM-dd") if one is set.
    static func on(_ date: Date, birthday: String = "", calendar: Calendar = .current) -> QuotaPetHoliday? {
        let day = calendar.dateComponents([.month, .day], from: date)
        guard let month = day.month, let dayOfMonth = day.day else { return nil }
        let parts = birthday.split(separator: "-").compactMap { Int($0) }
        if parts.count == 2, parts[0] == month, parts[1] == dayOfMonth { return .birthday }
        if (month == 10 && dayOfMonth >= 30) || (month == 11 && dayOfMonth == 1) { return .halloween }
        if month == 12 && (24...26).contains(dayOfMonth) { return .christmas }
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = calendar.timeZone
        let today = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        if today.isLeapMonth != true, let m = today.month, let d = today.day {
            if m == 8 && (14...16).contains(d) { return .midAutumn }
            if m == 1 && d <= 7 { return .springFestival }
        }
        if let next = calendar.date(byAdding: .day, value: 1, to: date) {
            let tomorrow = lunar.dateComponents([.month, .day, .isLeapMonth], from: next)
            if tomorrow.isLeapMonth != true && tomorrow.month == 1 && tomorrow.day == 1 { return .springFestival }
        }
        return nil
    }
}
