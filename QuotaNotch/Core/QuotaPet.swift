// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A small pixel pet that stands in for the closed-notch quota ring. It only reflects quota.
enum QuotaPetKind: String, CaseIterable, Sendable {
    case off, mochi, bit, jelly
    /// The chosen pet (never `off`); whether it shows is a separate switch.
    static let defaultsKey = "quotaPet"
    static let enabledKey = "quotaPetEnabled"
    static let defaultKind: QuotaPetKind = .bit
    static let pets: [QuotaPetKind] = [.mochi, .bit, .jelly]
    static func choice(_ raw: String?) -> QuotaPetKind {
        let kind = raw.flatMap(QuotaPetKind.init(rawValue:)) ?? defaultKind
        return kind == .off ? defaultKind : kind
    }
    /// What the notch shows: the chosen pet while pet mode is on, otherwise the original ring.
    static func effective(enabled: Bool, raw: String?) -> QuotaPetKind { enabled ? choice(raw) : .off }
}

/// `original` keeps the drawn colors; `service` tints one detail with the Claude or Codex color.
enum QuotaPetTint: String, CaseIterable, Sendable {
    case original, service
    static let defaultsKey = "quotaPetTint"
}

/// `widget` is the regular quota slot (20×16pt); `minimal` is the 16pt slot shared with tasks.
enum QuotaPetSize: Sendable { case widget, minimal }

enum QuotaPetMood: String, Sendable, Equatable, CaseIterable {
    /// Plenty left.
    case idle
    /// The reading dropped in the last few minutes.
    case working
    /// At the average rate so far, the window runs out before it resets.
    case pacing
    /// Less than 20% left.
    case low
    /// Nothing left until the reset.
    case empty
    /// The window just refilled.
    case refilled
    /// No fresh reading.
    case stale

    var animates: Bool { self == .working || self == .pacing || self == .refilled }
}

enum QuotaPace {
    /// True when, at the average rate used so far in this window, it empties before it resets.
    static func runsOutBeforeReset(_ window: QuotaWindow, now: Date) -> Bool {
        guard let reset = window.resetsAt, let period = window.period, period > 0 else { return false }
        let left = reset.timeIntervalSince(now)
        guard left > 0, left < period else { return false }
        let elapsed = period - left
        // Early in a window a single burst says little about the pace.
        guard elapsed >= min(15 * 60, period * 0.05) else { return false }
        let remaining = window.remainingPercent, used = 100 - remaining
        guard remaining > 0, used > 0 else { return false }
        return remaining / (used / elapsed) < left
    }
}

/// Remembers recent changes per window so the pet can react to them. Pure value type.
struct QuotaPetTracker: Sendable, Equatable {
    static let workingFor: TimeInterval = 5 * 60
    static let refilledFor: TimeInterval = 8

    private struct Sample: Sendable, Equatable { let value: Double; let date: Date }
    private var last: [String: Sample] = [:]
    private var lastDrop: [String: Date] = [:]
    private var lastRefill: [String: Date] = [:]

    static func key(provider: QuotaProvider, windowID: String) -> String { provider.rawValue + ":" + windowID }

    mutating func observe(key: String, remaining: Double, at date: Date) {
        if let previous = last[key] {
            // Readings can arrive out of order across refreshes; only newer ones count.
            guard date >= previous.date else { return }
            if remaining >= previous.value + 20 {
                lastRefill[key] = date
                lastDrop[key] = nil
            } else if remaining < previous.value - 0.05 {
                lastDrop[key] = date
            }
        }
        last[key] = Sample(value: remaining, date: date)
    }

    mutating func observe(_ snapshot: QuotaSnapshot, provider: QuotaProvider) {
        for window in snapshot.windows {
            observe(key: Self.key(provider: provider, windowID: window.id), remaining: window.remainingPercent, at: snapshot.fetchedAt)
        }
    }

    func mood(key: String, window: QuotaWindow?, stale: Bool, now: Date) -> QuotaPetMood {
        guard let window, !stale else { return .stale }
        let remaining = window.remainingPercent
        if remaining <= 0 { return .empty }
        if let date = lastRefill[key], now.timeIntervalSince(date) < Self.refilledFor { return .refilled }
        if remaining < 20 { return .low }
        if QuotaPace.runsOutBeforeReset(window, now: now) { return .pacing }
        if let date = lastDrop[key], now.timeIntervalSince(date) < Self.workingFor { return .working }
        return .idle
    }
}

/// A finished sprite: row-major ASCII codes, `.` is transparent.
struct QuotaPetSprite: Equatable, Sendable {
    let width: Int
    let height: Int
    let codes: [UInt8]
    func code(x: Int, y: Int) -> UInt8 { codes[y * width + x] }
    var rows: [String] {
        (0..<height).map { y in String(decoding: codes[(y * width)..<((y + 1) * width)], as: UTF8.self) }
    }
}

/// Pixel art for the three pets. One pixel is drawn as one point.
enum QuotaPetArt {
    static let frameInterval: TimeInterval = 0.42
    static let blinkPeriod: TimeInterval = 4

    private typealias Grid = [[UInt8]]
    private static let dot = UInt8(ascii: ".")

    private static let base: [QuotaPetKind: [String]] = [
        .mochi: [
            "...................",
            "..oo.......oo......",
            ".ogo.......opo.....",
            ".oggooooooooppo....",
            ".oggcccccccccpo....",
            "oggccccccccccco....",
            "occcccccccccccco...",
            "occcccccccccccco...",
            "ocpcccccccccpcco...",
            "occcccccccccccco...",
            ".osccccccccccso....",
            "..oosccccccsoo.....",
            ".o.osccccccso......",
            "oco.scccccccso.....",
            "oco.occocccocco....",
            ".oooooooooooooo...."
        ],
        .bit: [
            ".......o..........",
            "......oLo.........",
            ".......o..........",
            "..oooooooooooo....",
            ".occcccccccccco...",
            "occkkkkkkkkkkcco..",
            "ockkkkkkkkkkkkco..",
            "ockkkkkkkkkkkkco..",
            "ockkkkkkkkkkkkco..",
            "occkkkkkkkkkkcco..",
            ".occcccccccccco...",
            "..oooooooooooo....",
            "...osddddddso.....",
            "..oasddddddsao....",
            "...osssssssso.....",
            "....oo....oo......"
        ],
        .jelly: [
            "..................",
            "......oooooo......",
            "....ooccccccoo....",
            "...occcwwccccco...",
            "..occcwcccccccco..",
            "..occcccccccccco..",
            ".occcccccccccccco.",
            ".occcccccccccccco.",
            ".occcccccccccccco.",
            ".occcccccccccccco.",
            "occcccccccccccccco",
            "occcccccccccccccco",
            "occcccccccccccccco",
            ".occcccccccccccco.",
            "..oooooooooooooo..",
            ".................."
        ]
    ]
    private static let smallJelly = [
        "....oooooo....",
        "..ooccccccoo..",
        ".occwwcccccco.",
        ".ocwcccccccco.",
        "occcccccccccco",
        "occcccccccccco",
        "occcccccccccco",
        "occcccccccccco",
        ".occcccccccco.",
        "..oooooooooo.."
    ]
    private static let eyePositions: [QuotaPetKind: [(Int, Int)]] = [
        .mochi: [(4, 6), (10, 6)], .bit: [(4, 6), (10, 6)], .jelly: [(5, 7), (11, 7)]
    ]
    private static let mouthPositions: [QuotaPetKind: (Int, Int)] = [.mochi: (7, 9), .bit: (7, 8), .jelly: (8, 10)]
    private static let eyes: [String: [String]] = [
        "open": ["ee", "ee"], "closed": ["..", "oo"], "happy": [".o.", "o.o"],
        "wide": ["ee", "ee", "ee"], "tired": ["oo", "ee"], "down": ["..", "ee"]
    ]
    private static let mouths: [String: [String]] = [
        "smile": ["o.o", ".o."], "flat": ["ooo"], "open": [".o.", "omo", ".o."], "small": [".o."], "cat": ["o.o", ".o."]
    ]

    private struct Pose { var expression: String; var mouth: String }

    private static func pose(_ kind: QuotaPetKind, _ mood: QuotaPetMood, blink: Bool) -> Pose {
        switch mood {
        case .idle: return Pose(expression: blink ? "closed" : "open", mouth: kind == .bit ? "small" : "cat")
        case .working: return Pose(expression: "down", mouth: "small")
        case .pacing: return Pose(expression: "wide", mouth: "open")
        case .low: return Pose(expression: blink ? "closed" : "tired", mouth: "flat")
        case .empty, .stale: return Pose(expression: "closed", mouth: "small")
        case .refilled: return Pose(expression: "happy", mouth: "smile")
        }
    }

    static func sprite(_ kind: QuotaPetKind, size: QuotaPetSize, mood: QuotaPetMood,
                       remaining: Double, frame: Int = 0, blink: Bool = false) -> QuotaPetSprite {
        let q = min(100, max(0, remaining.isFinite ? remaining : 0))
        let grid: Grid
        switch size {
        case .widget: grid = crop(full(kind, mood: mood, props: true, remaining: q, frame: frame, blink: blink), x: 1, y: 1, width: 20, height: 16)
        case .minimal: grid = minimal(kind, mood: mood, remaining: q, blink: blink)
        }
        return QuotaPetSprite(width: grid.first?.count ?? 0, height: grid.count, codes: grid.flatMap { $0 })
    }

    private static func full(_ kind: QuotaPetKind, mood: QuotaPetMood, props: Bool,
                             remaining q: Double, frame: Int, blink: Bool) -> Grid {
        var grid = Grid(repeating: [UInt8](repeating: dot, count: 22), count: 18)
        guard kind != .off, var rows = base[kind] else { return grid }
        let ox = 1, oy = 1, even = frame % 2 == 0
        switch kind {
        case .jelly:
            let level = 13 - Int((11 * q / 100).rounded())
            rows = rows.enumerated().map { (y: Int, row: String) -> String in
                guard y >= level else { return row }
                let fill: Character = y == level ? "F" : "f"
                return String(row.map { $0 == "c" || $0 == "w" ? fill : $0 })
            }
        case .bit:
            var cells = Int((q / 100 * 6).rounded())
            if q > 0 && cells == 0 { cells = 1 }
            let meter = String(repeating: "m", count: cells) + String(repeating: "d", count: 6 - cells)
            rows[12] = "...os" + meter + "so....."
            rows[13] = "..oas" + meter + "sao...."
        default: break
        }
        paint(&grid, rows, ox, oy)
        if kind == .mochi {
            var fill = Int((q / 100 * 4).rounded())
            if q > 0 && fill == 0 { fill = 1 }
            paint(&grid, [fill >= 4 ? "..fff.." : (fill >= 3 ? "...f..." : ".......")], 14, 11)
            paint(&grid, [".......", fill >= 2 ? "offfffo" : (fill >= 1 ? "o.fff.o" : "o.....o"), "oBBBBBo", ".oBBBo."], 14, 12)
        }
        let look = Self.pose(kind, mood, blink: blink)
        let eye = eyes[look.expression] ?? eyes["open"]!
        let lift = look.expression == "wide" ? -1 : 0
        for (x, y) in eyePositions[kind] ?? [] { paint(&grid, eye, ox + x, oy + y + lift) }
        if let mouth = mouthPositions[kind] { paint(&grid, mouths[look.mouth] ?? mouths["cat"]!, ox + mouth.0, oy + mouth.1) }
        if kind == .bit {
            // Features on the screen glow instead of being outlined.
            let o = UInt8(ascii: "o"), e = UInt8(ascii: "e")
            for y in (oy + 5)...(oy + 9) { for x in (ox + 2)...(ox + 13) where grid[y][x] == o { grid[y][x] = e } }
        }
        guard props else { return grid }
        switch mood {
        case .working:
            paint(&grid, [".aaaaaaaa.", ".akkkkkka.", ".akeekka..", "ssssssssss"], ox + 2, oy + 11)
            if even { paint(&grid, ["oc"], ox + 2, oy + 13) } else { paint(&grid, ["co"], ox + 10, oy + 13) }
        case .low:
            paint(&grid, [".d.", "ddd", ".d."], ox + 14, oy + 3)
        case .refilled:
            paint(&grid, even ? [".w.", "www", ".w."] : ["w.w", ".w.", "w.w"], 18, 1)
            paint(&grid, even ? ["w"] : [".w.", "www", ".w."], 17, 6)
        case .pacing where kind != .jelly:
            paint(&grid, [".oo.", "occo", "occo", ".oco", "..o."], ox + 15, oy + (even ? 1 : 0))
        default: break
        }
        return grid
    }

    private static func minimal(_ kind: QuotaPetKind, mood: QuotaPetMood, remaining q: Double, blink: Bool) -> Grid {
        switch kind {
        case .off:
            return []
        case .jelly:
            let level = 8 - Int((7 * q / 100).rounded())
            var grid: Grid = smallJelly.enumerated().map { (y: Int, row: String) -> [UInt8] in
                guard y >= level && y >= 1 else { return Array(row.utf8) }
                let fill: UInt8 = y == level ? UInt8(ascii: "F") : UInt8(ascii: "f")
                return row.utf8.map { $0 == UInt8(ascii: "c") || $0 == UInt8(ascii: "w") ? fill : $0 }
            }
            let look = Self.pose(kind, mood, blink: blink)
            if look.expression == "happy" {
                paint(&grid, [".o.", "o.o"], 3, 4); paint(&grid, [".o.", "o.o"], 8, 4)
            } else {
                let eye = eyes[look.expression] ?? eyes["open"]!
                let lift = look.expression == "wide" ? -1 : 0
                paint(&grid, eye, 4, 4 + lift); paint(&grid, eye, 8, 4 + lift)
            }
            paint(&grid, look.mouth == "open" ? ["oo", "oo"] : ["oo"], 6, 6)
            return grid
        case .mochi:
            let head = full(kind, mood: mood, props: false, remaining: q, frame: 0, blink: blink)
            let food = UInt8(ascii: "f"), bowl = UInt8(ascii: "B")
            var grid = crop(head, x: 1, y: 2, width: 16, height: 10).map { $0.map { $0 == food || $0 == bowl ? dot : $0 } }
            grid.append([UInt8](repeating: dot, count: 16))
            grid.append(meter(width: 16, remaining: q, fill: UInt8(ascii: "f"), empty: UInt8(ascii: "x")))
            return grid
        case .bit:
            var grid = crop(full(kind, mood: mood, props: false, remaining: q, frame: 0, blink: blink), x: 1, y: 2, width: 16, height: 11)
            grid.append(meter(width: 16, remaining: q, fill: UInt8(ascii: "m"), empty: UInt8(ascii: "d")))
            return grid
        }
    }

    private static func meter(width: Int, remaining q: Double, fill: UInt8, empty: UInt8) -> [UInt8] {
        let cells = width - 2
        let filled = q > 0 ? max(1, Int((q / 100 * Double(cells)).rounded())) : 0
        var row = [dot]
        for index in 0..<cells { row.append(index < filled ? fill : empty) }
        row.append(dot)
        return row
    }

    private static func crop(_ grid: Grid, x: Int, y: Int, width: Int, height: Int) -> Grid {
        (y..<(y + height)).map { row in
            (x..<(x + width)).map { column in
                row < grid.count && column < grid[row].count ? grid[row][column] : dot
            }
        }
    }

    private static func paint(_ grid: inout Grid, _ rows: [String], _ x0: Int, _ y0: Int) {
        for (dy, row) in rows.enumerated() {
            for (dx, code) in row.utf8.enumerated() where code != dot {
                let y = y0 + dy, x = x0 + dx
                guard y >= 0, y < grid.count, x >= 0, x < grid[y].count else { continue }
                grid[y][x] = code
            }
        }
    }

    // MARK: Colors (0xRRGGBB)

    static func brandColor(_ provider: QuotaProvider) -> UInt32 { provider == .claude ? 0xE39B7A : 0x9ED4BF }

    /// Points per sprite pixel. Only whole device pixels keep the art crisp: 1.5 needs a
    /// Retina display, 2 needs a tall notch.
    static func pixelScale(size: NotchUISize, notchHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard notchHeight >= 30 else { return 1 }
        let retina = displayScale >= 2
        switch size {
        case .small: return 1
        case .standard: return retina ? 1.5 : 1
        case .large: return notchHeight >= 36 ? 2 : (retina ? 1.5 : 1)
        }
    }

    /// The color of the pet's own gauge (food, chest meter, water), for the bar beside it.
    static func gaugeColor(_ kind: QuotaPetKind, provider: QuotaProvider, tint: QuotaPetTint, remaining: Double) -> UInt32 {
        let palette = palette(kind, provider: provider, tint: tint, remaining: remaining)
        let warning: UInt32? = remaining < 20 ? 0xFF5A4F : (remaining < 35 ? 0xF4D35E : nil)
        switch kind {
        case .off: return 0xFFFFFF
        case .mochi: return warning ?? (tint == .service ? brandColor(provider) : palette[UInt8(ascii: "f")] ?? 0xF0B85A)
        case .bit: return palette[UInt8(ascii: "m")] ?? 0x5AD19A
        case .jelly: return palette[UInt8(ascii: "f")] ?? 0x7AA2FF
        }
    }

    static func palette(_ kind: QuotaPetKind, provider: QuotaProvider, tint: QuotaPetTint, remaining: Double) -> [UInt8: UInt32] {
        var colors: [Character: UInt32]
        switch kind {
        case .off: return [:]
        case .mochi:
            colors = ["o": 0x3B2C27, "c": 0xFFF4E4, "s": 0xEFD6B4, "g": 0x8F8782, "p": 0xF4A49B, "e": 0x2A1F1C, "w": 0xFFFFFF,
                      "m": 0xC96F66, "B": 0x4A6DBB, "f": 0xF0B85A, "k": 0x2E3A52, "x": 0x3A3226, "a": 0x9AA6B8, "d": 0x5B7FE0]
        case .bit:
            colors = ["o": 0x232A36, "c": 0xE9EEF5, "s": 0xC3CCD9, "k": 0x14202E, "e": 0x7FF0E0, "w": 0xFFFFFF, "p": 0xFF9F8F,
                      "a": 0x9AA6B8, "m": 0x5AD19A, "d": 0x3A4658, "L": 0x5AD19A]
        case .jelly:
            colors = ["o": 0x2D3A64, "c": 0xDFE8FF, "s": 0xC4D2FB, "e": 0x1D2547, "w": 0xFFFFFF, "p": 0xFFA3B8, "f": 0x7AA2FF,
                      "F": 0xA9C3FF, "d": 0x5B7FE0, "a": 0x9AA6B8, "k": 0x2E3A52, "m": 0xC96F66]
        }
        let brand = brandColor(provider)
        let warning: UInt32? = remaining < 20 ? 0xFF5A4F : (remaining < 35 ? 0xF4D35E : nil)
        if tint == .service {
            switch kind {
            case .bit: colors["e"] = brand
            case .jelly: colors["f"] = brand; colors["F"] = lighten(brand)
            case .mochi: colors["B"] = brand
            case .off: break
            }
        }
        if kind == .bit {
            let light = warning ?? (tint == .service ? brand : 0x5AD19A)
            colors["L"] = light; colors["m"] = light
        }
        if kind == .jelly, let warning { colors["f"] = warning; colors["F"] = lighten(warning) }
        var result: [UInt8: UInt32] = [:]
        for (key, value) in colors { result[UInt8(ascii: key.unicodeScalars.first!)] = value }
        return result
    }

    static func lighten(_ color: UInt32) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let value = Double((color >> shift) & 0xFF)
            return UInt32((value + (255 - value) * 0.45).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// Frame and blink state for a moment in time.
    static func frame(at date: Date) -> Int { Int(date.timeIntervalSinceReferenceDate / frameInterval) }
    static func blinking(at date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: blinkPeriod) < 0.15
    }

    /// When the pet next needs to be redrawn: every frame while animating, around each blink
    /// while resting, and otherwise only occasionally.
    static func nextRedraw(after date: Date, mood: QuotaPetMood) -> Date {
        if mood.animates {
            let next = (date.timeIntervalSinceReferenceDate / frameInterval).rounded(.down) + 1
            return Date(timeIntervalSinceReferenceDate: next * frameInterval + 0.001)
        }
        if mood == .idle || mood == .low {
            let t = date.timeIntervalSinceReferenceDate
            let start = (t / blinkPeriod).rounded(.down) * blinkPeriod
            let candidates = [start + 0.001, start + 0.16, start + blinkPeriod + 0.001]
            return Date(timeIntervalSinceReferenceDate: candidates.first { $0 > t + 0.0005 }!)
        }
        return date.addingTimeInterval(60)
    }
}
