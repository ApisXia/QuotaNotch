// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The small pixel pet that shows quota and tasks in the closed notch.
enum QuotaPetKind: String, CaseIterable, Sendable {
    case mochi, bit, jelly, ghost, sprout
    static let defaultsKey = "quotaPet"
    static let defaultKind: QuotaPetKind = .bit
    static let pets: [QuotaPetKind] = [.mochi, .bit, .jelly, .ghost, .sprout]
    /// The saved pet; older values such as "off" fall back to the default.
    static func choice(_ raw: String?) -> QuotaPetKind {
        raw.flatMap(QuotaPetKind.init(rawValue:)) ?? defaultKind
    }
}

/// `original` keeps the drawn colors; `service` tints one detail with the Claude or Codex color.
enum QuotaPetTint: String, CaseIterable, Sendable {
    case original, service
    static let defaultsKey = "quotaPetTint"
}

/// `widget` is the regular quota slot (20×16pt); `minimal` is the 16pt slot shared with tasks.
enum QuotaPetSize: Sendable { case widget, minimal }

/// How running and waiting tasks show around the pet. Each style uses one shape for both.
enum QuotaPetEffect: String, CaseIterable, Sendable {
    /// Soft rings from the middle; waiting adds faster rings and a glow.
    case soft
    /// Pixel ripples that follow the pet's outline; waiting recolors the outline itself.
    case pixel
    static let defaultsKey = "quotaPetEffect"
}

/// What the pet knows about tasks.
struct QuotaPetTasks: Equatable, Sendable {
    var waiting = 0
    var running = 0
    var lastCompletedAt: Date?
    static let none = QuotaPetTasks()
}

/// The effect drawn around the pet.
enum QuotaPetSignal: Equatable, Sendable { case none, running, waiting }

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
    /// A task waits for approval or an answer.
    case needsYou
    /// A task just finished.
    case celebrate

    var animates: Bool { [.working, .needsYou, .refilled, .celebrate].contains(self) }
}

/// Combines task and quota state into one pose. Waiting for the user always wins; the
/// quota keeps showing on the pet's gauge and in the numbers beside it.
enum QuotaPetBehavior {
    static let celebrateFor: TimeInterval = 6
    static func resolve(quota: QuotaPetMood, tasks: QuotaPetTasks, now: Date) -> (mood: QuotaPetMood, signal: QuotaPetSignal) {
        if tasks.waiting > 0 { return (.needsYou, .waiting) }
        if quota == .empty { return (.empty, .none) }
        if quota == .refilled { return (.refilled, .none) }
        if tasks.running == 0, let done = tasks.lastCompletedAt {
            let age = now.timeIntervalSince(done)
            if age >= 0 && age < celebrateFor { return (.celebrate, .none) }
        }
        if tasks.running > 0 { return (.working, .running) }
        return (quota, .none)
    }
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

/// Moments worth a short line below the notch while music takes the quota numbers' place.
enum QuotaPeekEvent: Equatable, Sendable {
    case crossed(Int)
    case refilled
    case pacing
}

enum QuotaPeekRule {
    static let thresholds = [0, 20, 50]
    static let duration: TimeInterval = 4

    /// Compares two readings of the same window. A refill wins, then the lowest threshold
    /// crossed on the way down, then the pace turning too fast.
    static func event(previous: Double?, current: Double, wasPacing: Bool, pacing: Bool) -> QuotaPeekEvent? {
        guard let previous else { return nil }
        if current >= previous + 20 { return .refilled }
        if let threshold = thresholds.first(where: { previous > Double($0) && current <= Double($0) }) {
            return .crossed(threshold)
        }
        if pacing && !wasPacing { return .pacing }
        return nil
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

/// Pixel art for the pets. One pixel is drawn as one point.
enum QuotaPetArt {
    static let frameInterval: TimeInterval = 0.42
    static let blinkPeriod: TimeInterval = 4

    private typealias Grid = [[UInt8]]
    private static let dot = UInt8(ascii: ".")

    private static let jellyBase: [String] = [
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
    private static let eyes: [String: [String]] = [
        "open": ["ee", "ee"], "closed": ["..", "oo"], "happy": [".o.", "o.o"],
        "wide": ["ee", "ee", "ee"], "tired": ["oo", "ee"], "down": ["..", "ee"]
    ]
    private struct Pose { var expression: String; var mouth: String }

    private static func pose(_ kind: QuotaPetKind, _ mood: QuotaPetMood, blink: Bool) -> Pose {
        switch mood {
        case .idle: return Pose(expression: blink ? "closed" : "open", mouth: kind == .bit ? "small" : "cat")
        case .working: return Pose(expression: "down", mouth: "small")
        case .pacing: return Pose(expression: "wide", mouth: "small")
        case .needsYou: return Pose(expression: "wide", mouth: "open")
        case .low: return Pose(expression: blink ? "closed" : "tired", mouth: "flat")
        case .empty, .stale: return Pose(expression: "closed", mouth: "small")
        case .refilled, .celebrate: return Pose(expression: "happy", mouth: "smile")
        }
    }

    static func sprite(_ kind: QuotaPetKind, size: QuotaPetSize, mood: QuotaPetMood,
                       remaining: Double, frame: Int = 0, blink: Bool = false) -> QuotaPetSprite {
        let q = min(100, max(0, remaining.isFinite ? remaining : 0))
        let grid: Grid
        switch (kind, size) {
        case (.mochi, .widget): grid = mochi(mood: mood, remaining: q, frame: frame, blink: blink, props: true)
        case (.bit, .widget): grid = bit(mood: mood, remaining: q, frame: frame, blink: blink, props: true)
        case (.jelly, .widget):
            var g = jellyBody(remaining: q)
            jellyFace(&g, mood: mood, frame: frame, blink: blink)
            // The slime is 18 pixels wide; one column in, it sits on the grid's middle.
            grid = shiftedRight(g, by: 1)
        case (.ghost, .widget): grid = ghost(mood: mood, remaining: q, frame: frame, blink: blink)
        case (.ghost, .minimal): grid = crop(ghost(mood: mood, remaining: q, frame: 0, blink: blink), x: 2, y: 1, width: 16, height: 12)
        case (.sprout, .widget): grid = sprout(mood: mood, remaining: q, frame: frame, blink: blink)
        case (.sprout, .minimal):
            // The leaves' middle rows over the pot.
            let whole = sprout(mood: mood, remaining: q, frame: 0, blink: blink)
            grid = crop(Array(whole[3...6]) + Array(whole[8...15]), x: 2, y: 0, width: 16, height: 12)
        case (_, .minimal): grid = minimal(kind, mood: mood, remaining: q, blink: blink)
        }
        return QuotaPetSprite(width: grid.first?.count ?? 0, height: grid.count, codes: grid.flatMap { $0 })
    }

    /// The jelly's body, filled with water up to the quota, before its face.
    private static func jellyBody(remaining q: Double) -> Grid {
        let level = 13 - Int((11 * q / 100).rounded())
        let rows = jellyBase.enumerated().map { (y: Int, row: String) -> String in
            guard y >= level else { return row }
            let fill: Character = y == level ? "F" : "f"
            return String(row.map { $0 == "c" || $0 == "w" ? fill : $0 })
        }
        var g = blank()
        paint(&g, rows, 0, 0)
        return g
    }

    private static func shiftedRight(_ grid: Grid, by dx: Int) -> Grid {
        grid.map { row in [UInt8](repeating: dot, count: dx) + row.prefix(row.count - dx) }
    }

    /// 麻薯: the cat with a big cup of tea beside her; the tea is the quota. Her face is
    /// centered on column 7.5; with the cup the whole pet fills the grid.
    private static func mochi(mood: QuotaPetMood, remaining q: Double, frame f: Int, blink: Bool, props: Bool) -> Grid {
        var g = blank()
        paint(&g, [
            "...................", "..oo.......oo......", ".ogo.......opo.....", ".oggooooooooppo....",
            ".oggcccccccccpo....", "oggccccccccccco....", "occcccccccccccco...", "occcccccccccccco...",
            "occcccccccccccco...", "occcccccccccccco...", ".osccccccccccso....", "..oosccccccsoo.....",
            ".o.osccccccso......", "oco.scccccccso.....", "oco.occocccocco....", ".oooooooooooooo...."
        ], 0, 0)
        let c = 7.5, closed = (mood == .idle && blink) || mood == .empty || mood == .stale
        if closed { mirrored(&g, ["..", "oo"], 4, 5, center: c) } else {
            switch mood {
            case .refilled, .celebrate: mirrored(&g, ["e.", ".e", "e."], 4, 4, center: c)
            case .working: mirrored(&g, ["..", "ee"], 4, 5, center: c)
            case .needsYou, .pacing: mirrored(&g, ["we", "ee", "ee"], 4, 4, center: c)
            case .low: mirrored(&g, ["oo", "ee"], 4, 5, center: c)
            default: mirrored(&g, ["we", "ee"], 4, 5, center: c)
            }
        }
        centered(&g, ["pp"], center: c, 7)
        g[8][2] = UInt8(ascii: "p"); g[8][13] = UInt8(ascii: "p")
        // a ω mouth with one little fang
        let mouth: [String]
        switch mood {
        case .needsYou: mouth = ["..oo..", ".oMMo.", "..oo.."]
        case .refilled, .celebrate: mouth = ["o.oo.o", ".oTTo.", "....w."]
        case .low: mouth = [".oooo."]
        case .working: mouth = ["o.oo.o", ".o..o."]
        default: mouth = ["o.oo.o", ".o..o.", "....w."]
        }
        paint(&g, mouth, 5, 8)
        if props {
            switch mood {
            case .working:
                paint(&g, [".aaaaaaaa.", ".akkkkkka.", ".akeekka..", "ssssssssss"], 2, 10)
                paint(&g, [f % 2 == 0 ? "oc" : "co"], f % 2 == 0 ? 2 : 10, 12)
            case .needsYou: paint(&g, [".oo.", "occo", "occo", ".oco", "..o."], 15, f % 2 == 0 ? 1 : 0)
            case .empty: sleepZ(&g, frame: f, 16, 0)
            case .low: drop(&g, frame: f, 14, 2)
            case .refilled, .celebrate: sparkle(&g, frame: f, 16, 0); paint(&g, ["w"], 17, 6)
            default: break
            }
        }
        // the cup: glass, with a handle on the right (the 16-point sprite shows her head only)
        guard props else { return g }
        for y in 9..<16 { for x in 14..<20 { g[y][x] = dot } }
        paint(&g, ["GGGGGG.", "GvvvvG.", "GvvvvGG", "GvvvvGG", "GvvvvGG", "GvvvvG.", ".GGGG.."], 13, 9)
        let tea = gaugeLevel(q, steps: 5)
        for i in 0..<tea { for x in 14...17 { g[14 - i][x] = UInt8(ascii: i == tea - 1 ? "F" : "f") } }
        if q > 0, mood != .needsYou, mood != .low {
            paint(&g, f % 2 == 0 ? [".S.S", "S.S."] : ["S.S.", ".S.S"], 14, 7)
        }
        return g
    }

    /// 比特: a little robot with a big head; LED eyes on its screen and an 8-cell charge meter
    /// on its belly. Drawn on 16 columns, then moved onto the grid's middle.
    private static func bit(mood: QuotaPetMood, remaining q: Double, frame f: Int, blink: Bool, props: Bool) -> Grid {
        var g = blank()
        paint(&g, [
            ".......o........", "......oLo.......", ".......o........", "..oooooooooooo..",
            ".occcccccccccco.", "occkkkkkkkkkkcco", "ockkkkkkkkkkkkco", "ockkkkkkkkkkkkco",
            "ockkkkkkkkkkkkco", "occkkkkkkkkkkcco", ".occcccccccccco.", "..oooooooooooo..",
            "..os########so..", ".oas########sao.", "..osssssssssso..", "....oo....oo...."
        ].map { $0.replacingOccurrences(of: "#", with: "d") }, 0, 0)
        let cells = gaugeLevel(q, steps: 8)
        for y in 12...13 { for i in 0..<8 { g[y][4 + i] = UInt8(ascii: i < cells ? "m" : "d") } }
        let c = 7.5
        switch mood {
        case .idle where blink: mirrored(&g, ["ee"], 4, 7, center: c)
        case .empty:
            mirrored(&g, ["ee"], 4, 7, center: c)
            paint(&g, ["DDD", ".D.", "DDD"], 10, 5)
        case .stale, .low: mirrored(&g, ["ee"], 4, 7, center: c)
        case .refilled, .celebrate: mirrored(&g, [".e.", "e.e"], 3, 5, center: c)
        case .needsYou, .pacing: mirrored(&g, ["ee", "ee", "..", "ee"], 4, 5, center: c)
        case .working: mirrored(&g, ["ee", "ee"], 4, 6, center: c)
        case .idle: mirrored(&g, ["ee", "ee", "ee"], 4, 5, center: c)
        }
        switch mood {
        case .refilled, .celebrate: centered(&g, ["e..e", ".ee."], center: c, 8)
        case .low: centered(&g, ["eeee"], center: c, 9)
        case .needsYou, .pacing, .empty, .stale: break
        default: centered(&g, ["ee"], center: c, 9)
        }
        if props && mood == .working {
            paint(&g, [".aaaaaaaa.", ".akkkkkka.", ".akeekka..", "ssssssssss"], 2, 10)
            paint(&g, [f % 2 == 0 ? "oc" : "co"], f % 2 == 0 ? 2 : 10, 12)
        }
        g = shiftedRight(g, by: 2)
        guard props else { return g }
        // Marks beside the head, drawn after centering so they stay inside the grid.
        switch mood {
        case .needsYou:
            paint(&g, [".oo.", "occo", "occo", ".oco", "..o."], 16, f % 2 == 0 ? 1 : 0)
            if f % 2 == 0 { g[1][9] = UInt8(ascii: "X") }
        case .refilled, .celebrate: sparkle(&g, frame: f, 17, 0)
        default: break
        }
        return g
    }

    // MARK: Pets with their own faces (from the approved design canvas)

    private static func blank(_ width: Int = 20, _ height: Int = 16) -> Grid {
        Grid(repeating: [UInt8](repeating: dot, count: width), count: height)
    }

    /// Paints `rows` at `x` and their mirror image around the center column `center`
    /// (9.5 for a 20-pixel pet), so faces are exactly symmetric.
    private static func mirrored(_ grid: inout Grid, _ rows: [String], _ x: Int, _ y: Int, center: Double,
                                 ink: ((UInt8, UInt8) -> UInt8)? = nil) {
        let width = rows.first?.utf8.count ?? 0
        paint(&grid, rows, x, y, ink: ink)
        paint(&grid, rows.map { String($0.reversed()) }, Int(2 * center + 1) - x - width, y, ink: ink)
    }

    /// Paints `rows` centered on `center`; their width must match it (even for x.5).
    private static func centered(_ grid: inout Grid, _ rows: [String], center: Double, _ y: Int) {
        let width = rows.first?.utf8.count ?? 0
        paint(&grid, rows, Int(center + 0.5) - width / 2, y)
    }

    /// Face pixels turn white where they sit on one of `dark`.
    private static func lightOn(_ dark: String) -> (UInt8, UInt8) -> UInt8 {
        let darkCodes = Set(dark.utf8), o = UInt8(ascii: "o"), e = UInt8(ascii: "e"), white = UInt8(ascii: "W")
        return { code, under in (code == o || code == e) && darkCodes.contains(under) ? white : code }
    }

    private static func shifted(_ grid: Grid, by dy: Int) -> Grid {
        guard dy != 0 else { return grid }
        return (0..<grid.count).map { y in
            let source = y - dy
            return source >= 0 && source < grid.count ? grid[source] : [UInt8](repeating: dot, count: grid[y].count)
        }
    }

    private static func gaugeLevel(_ q: Double, steps: Int) -> Int {
        q <= 0 ? 0 : max(1, Int((q / 100 * Double(steps)).rounded()))
    }

    private static func sparkle(_ grid: inout Grid, frame: Int, _ x: Int, _ y: Int) {
        paint(&grid, frame % 2 == 0 ? [".w.", "www", ".w."] : ["w.w", ".w.", "w.w"], x, y)
    }
    private static func sleepZ(_ grid: inout Grid, frame: Int, _ x: Int, _ y: Int) {
        paint(&grid, frame % 2 == 0 ? ["ZZZ", "..Z", ".Z.", "ZZZ"] : ["...", "ZZZ", ".Z.", "ZZZ"], x, y)
    }
    private static func bang(_ grid: inout Grid, frame: Int, _ x: Int, _ y: Int) {
        paint(&grid, frame % 2 == 0 ? ["X", "X", ".", "X"] : [".", "X", "X", ".", "X"], x, y)
    }
    private static func drop(_ grid: inout Grid, frame: Int, _ x: Int, _ y: Int, code: Character = "d") {
        let c = String(code)
        paint(&grid, [".\(c).", "\(c)\(c)\(c)", ".\(c)."], x, y + frame % 2)
    }

    /// 果冻: the existing slime, with big shiny eyes and its own reactions.
    private static func jellyFace(_ g: inout Grid, mood: QuotaPetMood, frame f: Int, blink: Bool) {
        let c = 8.5, ink = lightOn("fF")
        switch mood {
        case .empty, .stale: mirrored(&g, ["..", "..", "oo"], 5, 6, center: c, ink: ink)
        case .idle where blink: mirrored(&g, ["..", "..", "oo"], 5, 6, center: c, ink: ink)
        case .refilled, .celebrate: mirrored(&g, [".oo.", "o..o"], 4, 7, center: c, ink: ink)
        case .needsYou, .pacing: mirrored(&g, ["we", "ee", "ee", "ee"], 5, 5, center: c)
        case .low: mirrored(&g, ["..", "oo", "ee"], 5, 6, center: c, ink: ink)
        case .working: mirrored(&g, ["..", "we", "ee"], 5, 6, center: c)
        case .idle: mirrored(&g, ["we", "ee", "ee"], 5, 6, center: c)
        }
        switch mood {
        case .needsYou: centered(&g, ["MM", "MM"], center: c, 10)
        case .refilled, .celebrate: centered(&g, ["MM", "TT"], center: c, 10)
        default: centered(&g, ["MM"], center: c, 10)
        }
        let body = UInt8(ascii: "c"), water = UInt8(ascii: "f"), blush = UInt8(ascii: "p")
        for x in [3, 14] where g[9][x] == body || g[9][x] == water { g[9][x] = blush }
        switch mood {
        case .working:
            // bubbles rise in the water
            let y = 12 - (f % 3) * 2, bubble = UInt8(ascii: "w")
            if g[y][6] == water { g[y][6] = bubble }
            if y + 1 < g.count, g[y + 1][12] == water { g[y + 1][12] = bubble }
        case .empty:
            paint(&g, f % 2 == 0 ? [".bb.", "b..b", "b..b", ".bb."] : ["....", ".bb.", ".bb.", "...."], 11, 8)
        case .refilled, .celebrate:
            paint(&g, ["H.H", "HHH", ".H."], 0, 1 + f % 2)
            paint(&g, ["H.H", "HHH", ".H."], 15, 2 - f % 2)
        case .low:
            drop(&g, frame: f, 15, 2, code: "f")
        case .needsYou where f % 2 == 1:
            g = shifted(g, by: -1)
        default: break
        }
    }

    /// 飘飘: a little ghost; how solid it looks is the quota (see palette).
    private static func ghost(mood: QuotaPetMood, remaining q: Double, frame f: Int, blink: Bool) -> Grid {
        var g = blank()
        let wave = f % 2 == 1 ? 2 : 0
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < 20, y < 16, y >= 1, y <= 14 else { return false }
            if y <= 8 { let dx = Double(x) - 9.5, dy = Double(y) - 8; return dx * dx + dy * dy <= 7.2 * 7.2 }
            guard x >= 3, x <= 16 else { return false }
            if y >= 13 { let k = (x - 3 + wave) % 4; return y == 13 ? k != 3 : (k == 1 || k == 2) }
            return true
        }
        for y in 0..<16 { for x in 0..<20 where inside(x, y) {
            let edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
            g[y][x] = UInt8(ascii: edge ? "o" : (x >= 14 || y >= 12 ? "s" : "c"))
        } }
        paint(&g, ["hh", "h."], 5, 3)
        paint(&g, ["oo", "oco"], 1, 9); paint(&g, [".oo", "oco"], 16, 9)
        g[10][2] = UInt8(ascii: "c"); g[10][17] = UInt8(ascii: "s")
        // tall eyes and a two-pixel mouth, one blank row apart
        let eyeY = 6, c = 9.5
        switch mood {
        case .empty, .stale: mirrored(&g, ["..", "oo"], 6, eyeY, center: c)
        case .idle where blink: mirrored(&g, ["..", "oo"], 6, eyeY, center: c)
        case .working: mirrored(&g, [".", "e"], 7, eyeY, center: c)
        case .needsYou, .pacing: mirrored(&g, ["e", "e", "e"], 7, eyeY - 1, center: c)
        case .low: mirrored(&g, ["oo", ".e"], 6, eyeY, center: c)
        case .refilled, .celebrate: mirrored(&g, [".o.", "o.o"], 5, eyeY, center: c)
        case .idle: mirrored(&g, ["e", "e"], 7, eyeY, center: c)
        }
        switch mood {
        case .needsYou: centered(&g, ["MM", "MM"], center: c, eyeY + 3)
        case .refilled, .celebrate: centered(&g, ["MM", "TT"], center: c, eyeY + 3)
        default: centered(&g, ["MM"], center: c, eyeY + 3)
        }
        g[8][5] = UInt8(ascii: "p"); g[8][14] = UInt8(ascii: "p")
        let floats = [.idle, .working, .refilled, .celebrate].contains(mood)
        g = shifted(g, by: floats && f % 2 == 1 ? -1 : 0)
        switch mood {
        case .empty: sleepZ(&g, frame: f, 16, 0)
        case .low: drop(&g, frame: f, 16, 2)
        case .needsYou: bang(&g, frame: f, 18, 1)
        case .refilled, .celebrate:
            sparkle(&g, frame: f, 0, 0)
            paint(&g, f % 2 == 0 ? ["w"] : [".w.", "www", ".w."], 17, 4)
        default: break
        }
        return g
    }

    /// 苗苗: a sprout in a pot; the water band on the pot is the quota, and the leaves droop as it runs out.
    private static func sprout(mood: QuotaPetMood, remaining q: Double, frame f: Int, blink: Bool) -> Grid {
        var g = blank()
        paint(&g, [
            "...oooooooooooooo...", "...orrrrrrrrrrrro...", "....occcccccccco....", "....occcccccccco....",
            "....occcccccccco....", "....occcccccccco....", ".....onnnnnnnno.....", ".....oooooooooo....."
        ], 0, 8)
        let filled = gaugeLevel(q, steps: 8)
        for i in 0..<filled { g[14][6 + i] = UInt8(ascii: "m") }
        let up = [".ooo....ooo.", "olllo..olllo", "oLllLooLllLo", ".oLLLggLLLo.", "..oooggooo..", ".....gg.....", ".....gg....."]
        let flat = ["............", ".oooo..oooo.", "olllLooLlllo", ".ooooggoooo.", ".....gg.....", ".....gg.....", ".....gg....."]
        let droop = ["............", "............", "....oooo....", "...oyggyo...", ".oyyoggoyyo.", "oyyo.gg.oyyo", "oo...gg...oo"]
        let bare = ["............", "............", "............", ".....oo.....", "....oYYo....", ".....YY.....", ".....YY....."]
        let alert = ["...oo..oo...", "..olo..olo..", "..olo..olo..", "..oLoggoLo..", "...ooggoo...", ".....gg.....", ".....gg....."]
        var shape: [String]
        if q <= 0 { shape = bare }
        else if mood == .needsYou { shape = alert }
        else if q < 20 { shape = droop }
        else if q < 35 { shape = flat.map { $0.replacingOccurrences(of: "l", with: "y").replacingOccurrences(of: "L", with: "Y") } }
        else if q < 50 { shape = flat }
        else { shape = up }
        let sway = mood == .working && f % 2 == 1 ? 1 : 0
        paint(&g, shape, 4 + sway, 1)
        if mood == .refilled || mood == .celebrate { paint(&g, [".qq.", "qQQq"], 8, 0) }
        let c = 9.5
        switch mood {
        case .empty, .stale: mirrored(&g, ["oo"], 6, 11, center: c)
        case .idle where blink: mirrored(&g, ["oo"], 6, 11, center: c)
        case .refilled, .celebrate: mirrored(&g, [".o.", "o.o"], 6, 10, center: c)
        case .needsYou, .pacing: mirrored(&g, ["e", "e", "e"], 7, 10, center: c)
        case .low: mirrored(&g, ["o.", ".e"], 6, 10, center: c)
        case .idle, .working: mirrored(&g, ["e", "e"], 7, 10, center: c)
        }
        mirrored(&g, ["p"], 5, 12, center: c)
        centered(&g, mood == .refilled || mood == .celebrate ? ["TT"] : ["MM"], center: c, 13)
        switch mood {
        case .needsYou: bang(&g, frame: f, 17, 3)
        case .empty: sleepZ(&g, frame: f, 16, 2)
        case .refilled, .celebrate: sparkle(&g, frame: f, 1, 1)
        case .low: drop(&g, frame: f, 16, 5)
        default: break
        }
        return g
    }

    private static func minimal(_ kind: QuotaPetKind, mood: QuotaPetMood, remaining q: Double, blink: Bool) -> Grid {
        switch kind {
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
            // her head, without the cup, over a tea meter
            let head = mochi(mood: mood, remaining: q, frame: 0, blink: blink, props: false)
            var grid = crop(head, x: 0, y: 1, width: 16, height: 10)
            grid.append([UInt8](repeating: dot, count: 16))
            grid.append(meter(width: 16, remaining: q, fill: UInt8(ascii: "f"), empty: UInt8(ascii: "x")))
            return grid
        case .bit:
            var grid = crop(bit(mood: mood, remaining: q, frame: 0, blink: blink, props: false), x: 2, y: 1, width: 16, height: 11)
            grid.append(meter(width: 16, remaining: q, fill: UInt8(ascii: "m"), empty: UInt8(ascii: "d")))
            return grid
        case .ghost, .sprout:
            return sprite(kind, size: .minimal, mood: mood, remaining: q, blink: blink).rows.map { Array($0.utf8) }
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

    private static func paint(_ grid: inout Grid, _ rows: [String], _ x0: Int, _ y0: Int,
                              ink: ((UInt8, UInt8) -> UInt8)? = nil) {
        for (dy, row) in rows.enumerated() {
            for (dx, code) in row.utf8.enumerated() where code != dot {
                let y = y0 + dy, x = x0 + dx
                guard y >= 0, y < grid.count, x >= 0, x < grid[y].count else { continue }
                grid[y][x] = ink.map { $0(code, grid[y][x]) } ?? code
            }
        }
    }

    // MARK: Colors (0xRRGGBB)

    static func brandColor(_ provider: QuotaProvider) -> UInt32 { provider == .claude ? 0xE39B7A : 0x9ED4BF }

    /// Each pet's own color for task effects.
    static func themeColor(_ kind: QuotaPetKind) -> UInt32 {
        switch kind {
        case .mochi: return 0xF6B56B
        case .bit: return 0x6FF0D8
        case .jelly: return 0x7AA2FF
        case .ghost: return 0xB9C2FF
        case .sprout: return 0x8FDC6A
        }
    }

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

    /// The pet's width in the closed notch: the 20-pixel sprite at its scale, or the 16-point
    /// head on very short notches.
    static func petWidth(size: NotchUISize, notchHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        let scale = pixelScale(size: size, notchHeight: notchHeight, displayScale: displayScale)
        if scale > 1 { return 20 * scale }
        return QuotaCompactMetrics.iconSize(height: notchHeight, size: size) >= 18 ? 20 : 16
    }

    /// How far each side of the closed notch reaches. It depends only on the notch and the size
    /// setting, never on what is showing, so the notch keeps one width with or without music.
    /// The pet's width, or wider where the percentage ("100%") needs more room.
    static func wingWidth(size: NotchUISize, notchHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        max(petWidth(size: size, notchHeight: notchHeight, displayScale: displayScale), (size.percentFont * 2.4).rounded(.up))
    }

    /// The album cover sits centered in its side, 2 points below the notch's top and at least
    /// 5 points above its bottom, where the rounded corners are.
    static let albumTop: CGFloat = 2
    static func albumSize(size: NotchUISize, notchHeight: CGFloat, displayScale: CGFloat) -> CGFloat {
        max(0, min(wingWidth(size: size, notchHeight: notchHeight, displayScale: displayScale), notchHeight - albumTop - 5))
    }

    /// The color of the pet's own gauge (tea, chest meter, water), for the bar beside it.
    static func gaugeColor(_ kind: QuotaPetKind, provider: QuotaProvider, tint: QuotaPetTint, remaining: Double) -> UInt32 {
        let palette = palette(kind, provider: provider, tint: tint, remaining: remaining)
        let warning: UInt32? = remaining < 20 ? 0xFF5A4F : (remaining < 35 ? 0xF4D35E : nil)
        switch kind {
        case .mochi: return warning ?? (tint == .service ? brandColor(provider) : palette[UInt8(ascii: "f")] ?? 0xF0B85A)
        case .bit: return palette[UInt8(ascii: "m")] ?? 0x5AD19A
        case .jelly: return palette[UInt8(ascii: "f")] ?? 0x7AA2FF
        case .ghost: return warning ?? (tint == .service ? brandColor(provider) : 0xDFE3FB)
        case .sprout: return palette[UInt8(ascii: "m")] ?? 0x6FC3FF
        }
    }

    static func palette(_ kind: QuotaPetKind, provider: QuotaProvider, tint: QuotaPetTint, remaining: Double) -> [UInt8: UInt32] {
        var colors: [Character: UInt32]
        switch kind {
        case .mochi:
            colors = ["o": 0x3B2C27, "c": 0xFFF4E4, "s": 0xEFD6B4, "g": 0x8F8782, "p": 0xF4A49B, "e": 0x2A1F1C, "w": 0xFFFFFF,
                      "f": 0xF0B85A, "F": 0xF7D08A, "G": 0xC9D3E2, "v": 0x262C3A, "S": 0x9AA3B2, "k": 0x2E3A52, "x": 0x3A3226,
                      "a": 0x9AA6B8, "d": 0x7AA2FF, "M": 0x5A2E2E, "T": 0xFF7A8A, "Z": 0xCFD8E0]
        case .bit:
            colors = ["o": 0x232A36, "c": 0xE9EEF5, "s": 0xC3CCD9, "k": 0x14202E, "e": 0x7FF0E0, "w": 0xFFFFFF,
                      "a": 0x9AA6B8, "m": 0x5AD19A, "d": 0x3A4658, "L": 0x5AD19A, "D": 0x3F8A86, "X": 0xFF9F0A]
        case .jelly:
            colors = ["o": 0x2D3A64, "c": 0xDFE8FF, "s": 0xC4D2FB, "e": 0x1D2547, "w": 0xFFFFFF, "p": 0xFFA3B8, "f": 0x7AA2FF,
                      "F": 0xA9C3FF, "d": 0x5B7FE0, "a": 0x9AA6B8, "k": 0x2E3A52, "m": 0xC96F66,
                      "W": 0xFFFFFF, "M": 0x5A2E2E, "T": 0xFF7A8A, "H": 0xFF8FB1, "b": 0xBFE2FF]
        case .ghost:
            colors = ["o": 0x4B4F7A, "c": 0xF6F7FF, "s": 0xDFE3FB, "h": 0xFFFFFF, "e": 0x2B2F4A, "p": 0xFFB3C8, "w": 0xFFFFFF,
                      "M": 0x5A2E2E, "T": 0xFF7A8A, "Z": 0xCFD8E0, "X": 0xFF9F0A, "d": 0x7AA2FF]
        case .sprout:
            colors = ["o": 0x3A2A24, "c": 0xE58A5A, "r": 0xD1774A, "n": 0x8A4A32, "m": 0x6FC3FF, "g": 0x5AA14A, "l": 0x8FDC6A,
                      "L": 0x5AA14A, "y": 0xD9C25A, "Y": 0xB89A45, "q": 0xFF8FB1, "Q": 0xFFE27A, "e": 0x2A1F1C, "p": 0xF7B9A0,
                      "w": 0xFFFFFF, "M": 0x5A2E2E, "T": 0xFF7A8A, "Z": 0xCFD8E0, "X": 0xFF9F0A, "d": 0x7AA2FF]
        }
        let brand = brandColor(provider)
        let warning: UInt32? = remaining < 20 ? 0xFF5A4F : (remaining < 35 ? 0xF4D35E : nil)
        if tint == .service {
            switch kind {
            case .bit: colors["e"] = brand
            case .jelly: colors["f"] = brand; colors["F"] = lighten(brand)
            case .mochi: colors["f"] = brand; colors["F"] = lighten(brand)
            case .ghost: colors["p"] = brand
            case .sprout: colors["m"] = brand
            }
        }
        if kind == .bit {
            let light = warning ?? (tint == .service ? brand : 0x5AD19A)
            colors["L"] = light; colors["m"] = light
        }
        if kind == .jelly || kind == .mochi, let warning { colors["f"] = warning; colors["F"] = lighten(warning) }
        if kind == .sprout, let warning { colors["m"] = warning }
        if kind == .ghost {
            // The ghost fades as quota is used; the notch behind it is black, so fading is
            // blending toward black. The outline and face stay.
            let solid = 0.12 + 0.88 * min(100, max(0, remaining)) / 100
            for key in ["c", "s", "h", "p"] as [Character] { if let color = colors[key] { colors[key] = fade(color, solid) } }
        }
        var result: [UInt8: UInt32] = [:]
        for (key, value) in colors { result[UInt8(ascii: key.unicodeScalars.first!)] = value }
        return result
    }

    static func fade(_ color: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 { UInt32((Double((color >> shift) & 0xFF) * amount).rounded()) << shift }
        return channel(16) | channel(8) | channel(0)
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

struct QuotaPetCell: Equatable, Hashable, Sendable {
    let x: Int
    let y: Int
}

extension QuotaPetSprite {
    func isFilled(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && code(x: x, y: y) != UInt8(ascii: ".")
    }

    /// The same art with every pixel drawn as factor × factor pixels.
    func upscaled(_ factor: Int) -> QuotaPetSprite {
        guard factor > 1 else { return self }
        var codes: [UInt8] = []
        codes.reserveCapacity(width * height * factor * factor)
        for y in 0..<(height * factor) { for x in 0..<(width * factor) { codes.append(code(x: x / factor, y: y / factor)) } }
        return QuotaPetSprite(width: width * factor, height: height * factor, codes: codes)
    }

    /// Empty cells at each step (1...maxDistance) away from the art, following its outline.
    /// Coordinates are relative to the sprite and may be negative.
    func contours(maxDistance: Int) -> [[QuotaPetCell]] {
        let m = maxDistance, w = width + 2 * m, h = height + 2 * m
        var distance = [Int](repeating: -1, count: w * h)
        var queue: [(Int, Int)] = []
        for y in 0..<h { for x in 0..<w where isFilled(x - m, y - m) { distance[y * w + x] = 0; queue.append((x, y)) } }
        var index = 0
        while index < queue.count {
            let (x, y) = queue[index]; index += 1
            let next = distance[y * w + x] + 1
            guard next <= m else { continue }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h, distance[ny * w + nx] == -1 else { continue }
                distance[ny * w + nx] = next
                queue.append((nx, ny))
            }
        }
        var rings = [[QuotaPetCell]](repeating: [], count: m)
        for y in 0..<h { for x in 0..<w {
            let d = distance[y * w + x]
            if d >= 1 { rings[d - 1].append(QuotaPetCell(x: x - m, y: y - m)) }
        } }
        return rings
    }

    /// The art's own outline pixels.
    var outlineCells: [QuotaPetCell] {
        var cells: [QuotaPetCell] = []
        for y in 0..<height { for x in 0..<width where code(x: x, y: y) == UInt8(ascii: "o") { cells.append(QuotaPetCell(x: x, y: y)) } }
        return cells
    }
}
