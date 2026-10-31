// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The small pixel pet that shows quota and tasks in the closed notch.
enum QuotaPetKind: String, CaseIterable, Sendable {
    case mochi, bit, jelly, ghost, sprout, fish, pear, bbq, ox
    static let defaultsKey = "quotaPet"
    static let defaultKind: QuotaPetKind = .bit
    static let pets: [QuotaPetKind] = [.mochi, .bit, .jelly, .ghost, .sprout, .fish, .pear, .bbq, .ox]
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

    /// `touch` is a click reaction drawn into the art itself (the fish and the pear move inside
    /// their own sprite); the other pets react through `QuotaPetTouchPose` alone.
    static func sprite(_ kind: QuotaPetKind, size: QuotaPetSize, mood: QuotaPetMood,
                       remaining: Double, frame: Int = 0, blink: Bool = false,
                       touch: QuotaPetTouchMoment? = nil, outfit: QuotaPetHoliday? = nil) -> QuotaPetSprite {
        let q = min(100, max(0, remaining.isFinite ? remaining : 0))
        let live = touch.flatMap { $0.elapsed < $0.reaction.duration ? $0 : nil }
        // 麻薯's idle move is a stretch with its eyes closed.
        let blink = blink || (kind == .mochi && live?.reaction == .idleMove && (0.15..<1.5).contains(live?.elapsed ?? 0))
        var grid: Grid
        switch (kind, size) {
        case (.fish, .widget): grid = fish(mood: mood, remaining: q, frame: frame, touch: touch)
        case (.fish, .minimal): grid = crop(fish(mood: mood, remaining: q, frame: 0, touch: nil), x: 2, y: 4, width: 16, height: 12)
        case (.pear, .widget): grid = pear(mood: mood, remaining: q, frame: frame, blink: blink, touch: touch)
        case (.pear, .minimal): grid = crop(pear(mood: mood, remaining: q, frame: 0, blink: blink, touch: nil), x: 2, y: 4, width: 16, height: 12)
        case (.bbq, .widget): grid = bbq(mood: mood, remaining: q, frame: frame, blink: blink, touch: touch)
        case (.bbq, .minimal): grid = crop(bbq(mood: mood, remaining: q, frame: 0, blink: blink, touch: nil), x: 2, y: 2, width: 16, height: 12)
        case (.ox, .widget): grid = ox(mood: mood, remaining: q, frame: frame, touch: touch)
        case (.ox, .minimal): grid = crop(ox(mood: mood, remaining: q, frame: 0, touch: nil), x: 1, y: 3, width: 16, height: 12)
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
        if size == .widget, let live { acted(&grid, kind: kind, live) }
        if size == .widget, let outfit { dress(&grid, kind: kind, outfit) }
        return QuotaPetSprite(width: grid.first?.count ?? 0, height: grid.count, codes: grid.flatMap { $0 })
    }

    /// The reaction a pet acts out in its own art. Idle moves borrow a click reaction's moves:
    /// the fish swims its lap, the pear lifts its mountain, the sausage rolls over slowly.
    private static func acting(_ touch: QuotaPetTouchMoment?, _ kind: QuotaPetKind) -> (QuotaPetReaction?, TimeInterval) {
        guard let touch, touch.elapsed < touch.reaction.duration else { return (nil, 0) }
        let e = touch.elapsed
        guard touch.reaction == .idleMove else { return (touch.reaction, e) }
        switch kind {
        case .fish, .pear: return e < 1.3 ? (.pat, e) : (nil, 0)
        case .bbq: return e < 1.6 ? (.dizzy, e * 0.3) : (nil, 0)
        default: return (nil, 0)
        }
    }

    /// Art changes for celebrations and idle moves that a pose can't make.
    private static func acted(_ g: inout Grid, kind: QuotaPetKind, _ moment: QuotaPetTouchMoment) {
        let e = moment.elapsed
        let k = UInt8(ascii: "k"), led = UInt8(ascii: "e"), c = UInt8(ascii: "c")
        func clearFace() { for y in 5...9 { for x in 4...15 where g[y][x] == led { g[y][x] = k } } }
        switch (kind, moment.reaction) {
        case (.bit, .cheer) where e < 1.1:
            // a big tick on its screen
            clearFace()
            paint(&g, ["......e", ".....e.", "e...e..", ".e.e...", "..e...."], 6, 5)
        case (.bit, .idleMove) where e < 1.8:
            // screensaver: three dots, one hopping along
            clearFace()
            for x in [6, 9, 12] { g[7][x] = led }
            g[6][6 + (Int(e / 0.18) % 3) * 3] = led
        case (.sprout, .idleMove) where e > 0.6 && e < 1.3:
            // ^ ^ when the drop lands
            for y in 10...11 { for x in 0..<20 where g[y][x] == led { g[y][x] = c } }
            for (x, y) in [(7, 10), (12, 10), (6, 11), (8, 11), (11, 11), (13, 11)] { g[y][x] = led }
        case (.bbq, .cheer) where e > 0.5:
            // a bite out of the top right
            for y in 1...3 { for x in 10...13 {
                let d = (Double(x) - 13.5) * (Double(x) - 13.5) + (Double(y) - 0.8) * (Double(y) - 0.8)
                if d < 2.6 * 2.6 { g[y][x] = dot } else if d < 3.4 * 3.4 && g[y][x] == c { g[y][x] = UInt8(ascii: "o") }
            } }
        default:
            break
        }
    }

    /// A holiday hat on the pet's head: centered on the head, its brim on the head's top row.
    private static func dress(_ g: inout Grid, kind: QuotaPetKind, _ holiday: QuotaPetHoliday) {
        let (center, columns): (Double, ClosedRange<Int>) = kind == .mochi ? (7.5, 4...11) : kind == .ox ? (6.5, 3...10) : (9.5, 7...12)
        // Marks and sparkles above the head don't count as the head.
        let ignored = kind == .ox ? Set<UInt8>() : Set("ZzXwdH".utf8)
        let top = (0..<g.count).first { y in columns.contains { g[y][$0] != dot && !ignored.contains(g[y][$0]) } } ?? 15
        let hat = holiday.hat
        let width = hat[0].utf8.count
        let bottom = max(3, min(15, top + 1))
        paint(&g, hat, Int((center - Double(width) / 2 + 0.01).rounded()), bottom - hat.count + 1)
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

    // MARK: 芭比Q了 and 牛马

    /// How cooked the sausage is: 0 raw (plenty of quota) to 5 charred (none left).
    static func doneness(_ q: Double) -> Int { q >= 80 ? 0 : q >= 55 ? 1 : q >= 35 ? 2 : q >= 15 ? 3 : q > 0 ? 4 : 5 }
    private static let sausageColors: [(body: UInt32, outline: UInt32, marks: UInt32)] = [
        (0xFF9AA8, 0xC0566A, 0xE88A98), (0xF7A35C, 0xB9692F, 0xD07A3A), (0xD4783C, 0x8F4A22, 0x9A5228),
        (0x9A5228, 0x5E301A, 0x5A2E18), (0x5A3220, 0x33201A, 0x2E1A12), (0x2A201C, 0x120E0C, 0x050404)
    ]
    private static let sausage = ["..oooo..", ".occcco.", "occcccco", "occcccco", "occcccco", "occcccco", "occcccco",
                                  "occcccco", "occcccco", ".occcco.", "..oooo.."]
    private static let sausageSide = [".oo.", "occo", "occo", "occo", "occo", "occo", "occo", "occo", "occo", "occo", ".oo."]

    /// 芭比Q了: a sausage on a skewer over a grill. The less quota, the more cooked it is; at zero
    /// it's charred, with × × eyes and smoke.
    private static func bbq(mood: QuotaPetMood, remaining q: Double, frame f: Int, blink: Bool, touch: QuotaPetTouchMoment?) -> Grid {
        var g = blank()
        let (t, e) = acting(touch, .bbq)
        let still = touch?.reduceMotion ?? false
        let happy = mood == .refilled || mood == .celebrate
        let level = happy ? 0 : doneness(q)
        let charred = level == 5 && !happy
        let c = UInt8(ascii: "c"), j = UInt8(ascii: "j")
        // coals, grate and flames
        let glow = (f + (t != nil ? Int(e / 0.16) : 0)) % 2
        paint(&g, [charred ? "KKKKKKKKKKKK" : (glow == 1 ? "CKCCKCCKCCKC" : "KCCKCCKCCKCC")], 4, 15)
        paint(&g, ["gggggggggggggg"], 3, 14)
        paint(&g, ["g............g"], 3, 13)
        if !charred {
            let big = mood == .working || t == .annoyed || t == .open
            let flames = big ? (f % 2 == 1 ? [".F...F...F..", "FfF.FfF.FfF."] : ["F...F...F...", "fF.FfF.FfF.F"])
                             : (glow == 1 ? ["..F.....F...", ".FfF...FfF.."] : ["...F.....F..", "..FfF...FfF."])
            paint(&g, flames, 4, 12)
        }
        // the sausage on its skewer
        let sx = 6
        var sy = 1
        if mood == .needsYou && t == nil { sy = f % 2 == 1 ? 0 : 1 }
        var view = "front"
        if t == .dizzy && !still { view = ["front", "side", "back", "side"][Int(e / 0.12) % 4] }
        if t == .pat && e > 0.25 && e < 0.55 && !still { view = "side" }
        paint(&g, ["jj"], 9, 0)
        for y in 12...13 { g[y][9] = j; g[y][10] = j }
        paint(&g, view == "side" ? sausageSide : sausage, view == "side" ? 8 : sx, sy)
        if level >= 2 && view != "side" {
            // grill marks
            for y in (sy + 2)...(sy + 8) { for x in (sx + 1)...(sx + 6)
                where g[y][x] == c && (x + y + (view == "back" ? 2 : 0)) % 4 == 0 && (y - sy) % 3 != 1 { g[y][x] = UInt8(ascii: "m") } }
        }
        if view == "front" {
            if !charred { g[sy + 2][sx + 1] = UInt8(ascii: "h"); g[sy + 3][sx + 1] = UInt8(ascii: "h") }
            var eyes = ["e"], eyesR: [String]? = nil, mouth = ["MM"], cheek: String? = "p"
            switch mood {
            case .needsYou: eyes = ["e", "e"]; mouth = ["MM", "MM"]
            case .refilled, .celebrate: eyes = [".e.", "e.e"]; mouth = ["MM", "TT"]
            case .empty, .stale, .working: eyes = ["ee"]
            default:
                if level >= 3 { eyes = ["e.", ".e"]; eyesR = [".e", "e."]; mouth = [".MM.", "M..M"] }
                else if blink { eyes = ["ee"] }
            }
            if charred { eyes = ["x.x", ".x.", "x.x"]; eyesR = nil; mouth = ["xx"]; cheek = nil }
            switch t {
            case .pat: eyes = [".e.", "e.e"]; eyesR = nil; mouth = ["MM", "TT"]
            case .annoyed: eyes = ["e.", ".e", "e."]; eyesR = [".e", "e.", ".e"]; mouth = ["MM"]; cheek = "q"
            case .stir: if e < 0.75 { eyes = charred ? ["x.x", ".x.", "x.x"] : ["ee"]; eyesR = ["e"] }
            case .open: eyes = ["e", "e"]; mouth = ["MM", "MM"]
            default: break
            }
            let tall = eyes.count == 3, width = eyes[0].count
            let ey = sy + 4 - (eyes.count - 1) + (tall ? 1 : 0)
            paint(&g, eyes, sx + 3 - width, ey); paint(&g, eyesR ?? flipped(eyes), sx + 5, ey)
            paint(&g, mouth, sx + 4 - mouth[0].count / 2, sy + 6 + (tall ? 1 : 0))
            if let cheek { paint(&g, [cheek], sx + 1, sy + 6); paint(&g, [cheek], sx + 6, sy + 6) }
        }
        // oil drips while it works; smoke once it's done for; steam when it's cross
        if mood == .working && t == nil { paint(&g, f % 2 == 1 ? ["y"] : [".", "y"], 7 + (f % 2) * 4, sy + 11) }
        if charred { paint(&g, f % 2 == 1 ? [".SS...", "S..S.."] : ["..SS..", ".S..S."], 12, 0) }
        if t == .annoyed { paint(&g, Int(e / 0.15) % 2 == 1 ? ["S.S", ".S."] : [".S.", "S.S"], 12, 0) }
        if t == nil {
            switch mood {
            case .needsYou: bang(&g, frame: f, 17, 1)
            case .empty where !charred: sleepZ(&g, frame: f, 16, 0)
            case .low, .pacing: drop(&g, frame: f, 15, 3)
            case .refilled, .celebrate: sparkle(&g, frame: f, 1, 1)
            default: break
            }
        }
        if t == .open { bang(&g, frame: f, 17, 1) }
        return g
    }

    private static let cowHead = ["H..........H", ".HHooooooHH.", "EoccccKKKcoE", "EoccccccKcoE", ".occcccccco.",
                                  ".onnnnnnnno.", ".onknnnnkno.", "..oooooooo.."]
    private static let cowBody = ["..occcKcco..", "..oKKcccco..", "..oooooooo..", "..kk....kk.."]

    /// 牛马: a little cow hitched to a cart. Every sixth of the quota used is one more box on the cart.
    private static func ox(mood: QuotaPetMood, remaining q: Double, frame f: Int, touch: QuotaPetTouchMoment?) -> Grid {
        var g = blank()
        let (t, e) = acting(touch, .ox)
        let still = touch?.reduceMotion ?? false
        let lying = (mood == .empty || mood == .stale) && t != .open
        let pulling = mood == .working || mood == .low || mood == .pacing
        let happy = mood == .refilled || mood == .celebrate
        // the cart and its boxes
        paint(&g, ["jjjjjjj"], 13, 14)
        paint(&g, [".k...k."], 13, 15)
        let boxes = happy ? 0 : Int(((100 - max(0, q)) / 100 * 6).rounded())
        for i in 0..<boxes {
            var bx = 14, by = 12 - i * 2
            if t == .dizzy && !still {
                // the pile sways and the top box falls off
                bx += Int((sin(e / 0.12) * Double(i) * 0.35).rounded())
                if i == boxes - 1 && e > 1 { bx += 2 + Int((e - 1) / 0.2); by += Int((e - 1) / 0.09) }
            }
            if t == .annoyed && e < 0.6 && i >= 2 && !still && alternate(e, 0.06) > 0 { bx += 1 }
            paint(&g, i % 2 == 1 ? ["BBBBB", "BbbbB"] : ["BBBBB", "BBbBB"], bx, by)
        }
        // the cow
        var oy = 3
        if lying { oy = 5 }
        if happy && t == nil { oy = 3 - f % 2 }
        if pulling && t == nil { oy = 3 + f % 2 }
        if t == .open && !still { oy = 3 + min(0, hop(e)) }
        paint(&g, lying ? ["..oooooooo.."] : cowBody, 1, oy + 8)
        // the rope to the cart
        for (x, y) in [(11, oy + 8), (12, (oy + 8 + 13) / 2), (13, 13)] where y >= 0 && y < 16 { g[y][x] = UInt8(ascii: "r") }
        paint(&g, cowHead, 1, oy)
        func set(_ x: Int, _ y: Int, _ code: Character) {
            guard y >= 0, y < 16, x >= 0, x < 20 else { return }
            g[y][x] = UInt8(ascii: code.unicodeScalars.first!)
        }
        if t == .pat && Int(e / 0.13) % 2 == 0 {
            // ears flap
            g[oy + 2][1] = dot; g[oy + 2][12] = dot; set(1, oy + 1, "E"); set(12, oy + 1, "E")
        }
        // eyes: two pixels tall, in columns 4 and 9
        var look = "open"
        if lying { look = "closed" }
        if happy { look = "happy" }
        if mood == .low || mood == .pacing { look = "tired" }
        if mood == .working && t == nil { look = "down" }
        switch t {
        case .pat: look = "happy"
        case .annoyed: look = "roll"
        case .dizzy: look = ["roll", "open", "rollR", "open"][Int(e / 0.11) % 4]
        case .stir: look = e < 0.75 ? "peek" : "closed"
        case .open: look = "open"
        case .cheer, .idleMove, nil: break
        }
        let ey = oy + 4
        for (x, out) in [(4, -1), (9, 1)] {
            switch look {
            case "open": set(x, ey, "e"); set(x, ey - 1, "e")
            case "peek" where out > 0: set(x, ey, "e"); set(x, ey - 1, "e")
            case "closed", "peek": set(x + out, ey, "e"); set(x, ey, "e")
            case "happy": set(x - 1, ey, "e"); set(x, ey - 1, "e"); set(x + 1, ey, "e")
            case "down": set(x, ey, "e"); set(x + out, ey, "e")
            case "tired": set(x, ey - 1, "e"); set(x, ey, "V"); set(x + out, ey, "V")
            case "roll": set(x, ey - 1, "e"); set(x, ey, "G")
            case "rollR": set(x + out, ey - 1, "e"); set(x, ey, "G"); set(x, ey - 1, "G")
            default: break
            }
        }
        // a moo when it needs you
        if mood == .needsYou || t == .open { for x in 5...8 { set(x, oy + 7, "M") }; set(6, oy + 6, "M"); set(7, oy + 6, "M") }
        if mood == .low && t == nil { set(7, oy + 7, "T") }
        if happy || t == .pat { set(3, ey, "p"); set(10, ey, "p") }
        if t == .annoyed { let s = Int(e / 0.15) % 2; set(1 + s, oy + 7, "S"); set(12 - s, oy + 7, "S") }
        if pulling && t == nil { paint(&g, ["d", "d"], 0, oy - 2 + f % 2) }
        if t == nil {
            switch mood {
            case .needsYou: bang(&g, frame: f, 0, 0)
            case .empty: sleepZ(&g, frame: f, 0, 0)
            case .refilled, .celebrate: sparkle(&g, frame: f, 15, 8); sparkle(&g, frame: f + 1, 0, 0)
            default: break
            }
        }
        return g
    }

    // MARK: 摸鱼 and 鸭梨

    private static let fishRight = ["...ff..", "f.ffffo", "fffffef", "f.fbbff", "...f..."]
    private static let fishSleep = ["...ff..", "f.ffffo", "fffffcc", "f.fbbff", "...f..."]
    private static let fishHappy = ["...ff..", "f.ffffo", "ffffeff", "f.ffbMf", "...f..."]
    /// Tapped on the glass three times: a round, spiky pufferfish.
    private static let fishPuff = [".o.o.o.", "offfffo", "fefffef", "fffMfff", "ofbbbfo", ".o.o.o."]

    private static func flipped(_ rows: [String]) -> [String] { rows.map { String($0.reversed()) } }
    /// -1 / 1, switching every `period` seconds.
    private static func alternate(_ e: TimeInterval, _ period: TimeInterval) -> Int { Int(e / period) % 2 == 1 ? 1 : -1 }
    /// The hop used by the reactions, in sprite pixels (negative is up).
    static func hop(_ e: TimeInterval) -> Int { e < 0.15 ? -2 : e < 0.3 ? -3 : e < 0.45 ? -1 : e < 0.6 ? 0 : e < 0.7 ? -1 : 0 }

    /// 摸鱼: a goldfish in a round bowl; the water is the quota. Clicks happen inside the bowl:
    /// a lap with bubbles, a pufferfish, a whirlpool, a leap out of the water.
    private static func fish(mood: QuotaPetMood, remaining q: Double, frame f: Int, touch: QuotaPetTouchMoment?) -> Grid {
        var g = blank()
        let (t, e) = acting(touch, .fish)
        let still = touch?.reduceMotion ?? false
        let G = UInt8(ascii: "G"), v = UInt8(ascii: "v"), u = UInt8(ascii: "u"), U = UInt8(ascii: "U"), B = UInt8(ascii: "B")
        func inside(_ x: Int, _ y: Int) -> Bool {
            let dx = Double(x) - 9.5, dy = Double(y) - 9
            return y >= 4 && y <= 15 && dx * dx / (8.2 * 8.2) + dy * dy / (6.6 * 6.6) <= 1
        }
        let water = q > 0, level = 15 - gaugeLevel(q, steps: 10)
        // A tap on the glass makes the water slosh.
        let slosh = (t == .pat || t == .annoyed) && e < 0.6 && !still ? alternate(e, 0.12) : 0
        for y in 0..<16 { for x in 0..<20 where inside(x, y) {
            let edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y + 1) || !inside(x, y - 1)
            let surface = level + (x < 10 ? slosh : -slosh)
            g[y][x] = edge ? G : (water && y >= surface ? (y == surface ? U : u) : v)
        } }
        if t == .dizzy && water && !still {
            // a whirlpool
            for x in 2..<18 { for y in level..<15 where g[y][x] == u && (x + y + Int(e / 0.09)) % 5 == 0 { g[y][x] = U } }
        }
        paint(&g, ["GGGGGGGGGGGG"], 4, 3)
        paint(&g, ["h", "h", ".", "h"], 4, 6)

        let base = water ? min(10, max(level, 8) - 1) : 10
        var fx = 6, fy = base, face = fishRight
        switch mood {
        case .working, .pacing: fx = f % 2 == 1 ? 9 : 4; face = f % 2 == 1 ? fishRight : flipped(fishRight)
        case .idle: fx = f % 2 == 1 ? 7 : 6; fy = base + (f % 2 == 1 ? 0 : 1)
        case .refilled, .celebrate: fx = f % 2 == 1 ? 7 : 6; fy = base + (f % 2 == 1 ? 0 : 1); face = fishHappy
        case .needsYou: fy = f % 2 == 1 ? 0 : 1; fx = 7
        case .empty, .stale: face = fishSleep
        case .low: break
        }
        fy = min(fy, 10)

        switch t {
        case .pat:
            let r = e / QuotaPetReaction.pat.duration
            face = fishHappy
            if still { fx = 6; fy = base }
            else if water && r < 0.8 {
                // one happy lap around the bowl
                let a = r / 0.8 * 2 * .pi
                fx = 6 + Int((3.5 * cos(a)).rounded()); fy = min(10, base - 1 + Int((1.5 * sin(a)).rounded()))
                if sin(a) > 0 { face = flipped(fishHappy) }
            } else if !water { fy = 10 + min(0, hop(e)) }
            else { fx = 6; fy = base }
            if water {
                // a string of bubbles from its mouth
                for k in 0..<3 {
                    let by = fy + 1 - ((Int(e / 0.11) + k * 2) % 7), bx = fx + (face == fishHappy ? 7 : -1) + k % 2
                    if by >= 0, by < 16, bx >= 0, bx < 20, g[by][bx] == u || g[by][bx] == U { g[by][bx] = B }
                }
            }
        case .annoyed:
            face = fishPuff; fx = 6; fy = min(9, base)
        case .dizzy:
            if water && e < 1.5 && !still {
                let a = e / 0.17
                fx = 6 + Int((3 * cos(a)).rounded()); fy = min(10, base - 1 + Int((1.5 * sin(a)).rounded()))
                face = sin(a) > 0 ? flipped(fishRight) : fishRight
            } else { face = fishRight; fy = base }
        case .stir:
            face = e < 0.75 ? fishRight : fishSleep
            fy = 10 + (e > 0.15 && e < 0.45 && !still ? -1 : 0)
        case .open:
            fx = 7; face = fishHappy
            fy = still ? base : max(0, Int((Double(base) - Double(base + 1) * sin(.pi * min(1, e / 0.7))).rounded()))
            if e < 0.25 || e > 0.55 { paint(&g, ["d.d", ".d."], 3, 2); paint(&g, ["d.d", ".d."], 14, 2) }
        case .cheer, .idleMove, nil: break
        }
        paint(&g, face, fx, fy)

        if t == nil {
            switch mood {
            case .empty: sleepZ(&g, frame: f, 16, 0)
            case .low, .pacing: drop(&g, frame: f, 15, 2)
            case .needsYou:
                bang(&g, frame: f, 17, 1)
                paint(&g, ["d.d", ".d."], 4, 3 + f % 2); paint(&g, ["d.d"], 13, 3 + (f + 1) % 2)
            case .refilled, .celebrate: paint(&g, ["H.H", "HHH", ".H."], 13, f % 2); sparkle(&g, frame: f, 2, 0)
            default: break
            }
            if [.idle, .working, .refilled, .celebrate].contains(mood) {
                let by = 7 - (f % 2) * 2, bx = fx + 7
                if bx < 20, g[by][bx] == u || g[by][bx] == U { g[by][bx] = B }
            }
        }
        if t == .open { bang(&g, frame: f, 17, 1) }
        return g
    }

    /// 鸭梨 (鸭梨山大): a duck-billed pear holding up a mountain that grows as quota runs out.
    private static func pear(mood: QuotaPetMood, remaining q: Double, frame f: Int, blink: Bool, touch: QuotaPetTouchMoment?) -> Grid {
        var g = blank()
        let (t, e) = acting(touch, .pear)
        let still = touch?.reduceMotion ?? false
        let happy = mood == .refilled || mood == .celebrate
        let pressure = pearPressure(mood: mood, remaining: q)
        let squash = pressure >= 3
        var body = ["....oooo....", "...occcco...", "...occccso..", "..occcccsso.", ".occcccccsso", "occccccccsso",
                    "occccccccsso", "occccccccsso", ".occcccccso.", "..oooooooo.."]
        if squash { body.remove(at: 2) }
        let top = 16 - body.count
        paint(&g, body, 4, top)

        let billOpen = ["bbbb", "bMMb", "bbbb"], billSmile = ["bbbb", "bTTb", ".bb."]
        var eyes: [String], eyesR: [String]? = nil, bill: [String]
        switch mood {
        case .empty, .stale: eyes = ["ee"]
        case .refilled, .celebrate: eyes = [".e.", "e.e"]
        case .needsYou: eyes = ["e", "e"]
        default: eyes = blink ? ["ee"] : (pressure >= 3 || mood == .pacing ? ["e.", ".e"] : ["e", "e"])
        }
        switch mood {
        case .needsYou: bill = billOpen
        case .refilled, .celebrate: bill = billSmile
        default: bill = pressure >= 3 || mood == .pacing ? [".bb.", "bbbb"] : ["bbbb", ".bb."]
        }
        var cheek = ["p"], lift = 0, wobble = (mood == .needsYou || mood == .working) && f % 2 == 1 ? 1 : 0
        var leaf = ["..ll.", ".lln.", "...n."], sweat = true

        switch t {
        case .pat:
            eyes = [".e.", "e.e"]
            bill = e < 0.7 && Int(e / 0.14) % 2 == 0 ? billOpen : billSmile
            // it lifts the mountain off its head for a moment
            lift = pressure > 0 ? (e < 0.12 || e > 1 ? 0 : (e < 0.22 || e > 0.9 ? 1 : 2)) : 0
            sweat = false
            if pressure == 0 && !still {
                leaf = [["..ll.", ".lln.", "...n."], [".....", ".lln.", ".lln."], [".ll..", ".nll.", ".n..."], [".....", ".nll.", ".nll."]][Int(e / 0.11) % 4]
            }
        case .annoyed:
            eyes = ["e.", ".e", "e."]; eyesR = [".e", "e.", ".e"]
            bill = ["bbbb", "bbbb"]; cheek = ["qq"]
            wobble = e < 0.6 && !still ? -alternate(e, 0.06) : 0
        case .dizzy:
            eyes = [["ee", ".."], [".e", ".e"], ["..", "ee"], ["e.", "e."]][Int(e / 0.11) % 4]; eyesR = eyes
            bill = ["bbbb", ".bb."]
            wobble = still ? 0 : Int((sin(e / 0.12) * 1.5).rounded())
        case .stir:
            if e < 0.75 { eyes = ["ee"]; eyesR = ["e"] }
        case .open:
            eyes = ["e", "e"]; bill = billOpen
            // a jump with the mountain held up high
            lift = pressure > 0 && e > 0.1 && e < 0.6 ? 1 : 0
        case .cheer, .idleMove, nil: break
        }

        let fy = top + (squash ? 4 : 5)
        let tall = eyes.count == 3, width = eyes[0].count
        let ey = tall ? fy - 1 : fy - eyes.count + 1
        paint(&g, eyes, 8 - width, ey); paint(&g, eyesR ?? flipped(eyes), 12, ey)
        paint(&g, bill, 8, fy + 1)
        let cy = tall ? fy + 2 : fy + 1
        paint(&g, cheek, 7 - cheek[0].count, cy); paint(&g, cheek, 13, cy)

        if pressure == 0 {
            paint(&g, leaf, 7 + (happy && f % 2 == 1 && t == nil ? 1 : 0), top - 3)
        } else {
            let mountains: [[String]] = [
                ["...WW...", "..rrrr..", ".rrrRrr."],
                ["....W....", "...WWW...", "..rrWrr..", ".rrrrRrr."],
                ["....WW....", "...WWWW...", "..rrWWrr..", ".rrrrrrRr."],
                [".....WW.....", "....WWWW....", "...rWWWrr...", "..rrrrrrRr..", ".rrRrrrrrrr."]
            ]
            let mountain = mountains[pressure - 1], w = mountain[0].count
            let mx = Int((10 - Double(w) / 2).rounded()) + wobble, base = top - 2 - lift
            paint(&g, mountain, mx, base - mountain.count + 1)
            paint(&g, ["n"], 9, top - 1)
            // little arms reach up from the shoulders to the mountain's base
            func arm(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
                let n = max(abs(x1 - x0), abs(y1 - y0))
                guard n > 0 else { return }
                for i in 0...n {
                    let x = Int((Double(x0) + Double(x1 - x0) * Double(i) / Double(n)).rounded())
                    let y = Int((Double(y0) + Double(y1 - y0) * Double(i) / Double(n)).rounded())
                    if y >= 0, y < 16, x >= 0, x < 20, g[y][x] == dot { g[y][x] = i == n ? UInt8(ascii: "c") : UInt8(ascii: "a") }
                }
            }
            arm(5, top + 3, mx + 1, base + 1); arm(14, top + 3, mx + w - 2, base + 1)
            if sweat && t == nil {
                if pressure >= 2 { paint(&g, ["d", "d"], 3 - f % 2, top + 5) }
                if pressure >= 3 { paint(&g, ["d", "d"], 17 + f % 2, top + 4) }
            }
        }
        if t == nil {
            switch mood {
            case .needsYou: bang(&g, frame: f, 18, 0)
            case .empty: sleepZ(&g, frame: f, 16, 0)
            case .refilled, .celebrate: sparkle(&g, frame: f, 1, 2)
            default: break
            }
        }
        if t == .open { bang(&g, frame: f, 18, 0) }
        return g
    }

    /// How big the pear's mountain is: none with plenty of quota (or just refilled), four steps as it runs out.
    static func pearPressure(mood: QuotaPetMood, remaining q: Double) -> Int {
        if mood == .refilled || mood == .celebrate { return 0 }
        return q >= 80 ? 0 : q >= 55 ? 1 : q >= 35 ? 2 : q >= 15 ? 3 : 4
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
        case .ghost, .sprout, .fish, .pear, .bbq, .ox:
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
        case .fish: return 0xFF9F4A
        case .pear: return 0xDFE874
        case .bbq: return 0xFF6A2A
        case .ox: return 0xD9A85F
        }
    }

    /// The color of the task effects (glow, rings, ripples): the pet's own, or the service's
    /// when the pet is tinted by service.
    static func themeColor(_ kind: QuotaPetKind, provider: QuotaProvider, tint: QuotaPetTint) -> UInt32 {
        tint == .service ? brandColor(provider) : themeColor(kind)
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

    /// The album cover mirrors the pet: a square as tall as the pet (16 pixels at its scale),
    /// centered in its side on the same middle line.
    static func albumSize(size: NotchUISize, notchHeight: CGFloat, displayScale: CGFloat) -> CGSize {
        let side = 16 * pixelScale(size: size, notchHeight: notchHeight, displayScale: displayScale)
        return CGSize(width: side, height: side)
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
        case .fish: return palette[UInt8(ascii: "u")] ?? 0x5FB3FF
        case .pear: return warning ?? (tint == .service ? brandColor(provider) : 0xDFE874)
        case .bbq: return warning ?? (tint == .service ? brandColor(provider) : sausageColors[doneness(remaining)].body)
        case .ox: return warning ?? (tint == .service ? brandColor(provider) : 0xD9A85F)
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
        case .fish:
            colors = ["G": 0xC9D3E2, "h": 0xFFFFFF, "v": 0x1D2433, "u": 0x5FB3FF, "U": 0x9FD4FF, "f": 0xFF9F4A, "o": 0xE0702A,
                      "b": 0xFFE2C2, "c": 0x2A1F1C, "e": 0x2A1F1C, "B": 0xE8F6FF, "M": 0x5A2E2E, "T": 0xFF7A8A, "X": 0xFF9F0A,
                      "Z": 0xCFD8E0, "w": 0xFFFFFF, "d": 0x7AA2FF, "H": 0xFF8FB1]
        case .pear:
            colors = ["o": 0x4D5A1F, "c": 0xDFE874, "s": 0xB9C64E, "a": 0x8D9A35, "l": 0x5AA14A, "n": 0x7A4A2A, "r": 0x8A8F99,
                      "R": 0x6C717B, "W": 0xF2F4F8, "e": 0x2A1F1C, "b": 0xFF9F2A, "d": 0x7AA2FF, "q": 0xFF6B6B, "p": 0xFFA3B8,
                      "M": 0x5A2E2E, "T": 0xFF7A8A, "X": 0xFF9F0A, "Z": 0xCFD8E0, "w": 0xFFFFFF]
        case .bbq:
            let cooked = sausageColors[doneness(remaining)]
            colors = ["o": cooked.outline, "c": cooked.body, "m": cooked.marks, "h": 0xFFE0E6, "e": 0x2A140A, "x": 0xD8D8D8,
                      "q": 0xFF6B6B, "j": 0xE8C48A, "g": 0x7A7F88, "C": 0xFF6A2A, "K": 0x7A2A14, "F": 0xFFCF3A, "f": 0xFF6A2A,
                      "y": 0xFFD34D, "S": 0x9AA0AA, "p": 0xFFA3B8, "M": 0x5A2E2E, "T": 0xFF7A8A, "X": 0xFF9F0A, "Z": 0xCFD8E0,
                      "w": 0xFFFFFF, "d": 0x7AA2FF]
        case .ox:
            colors = ["o": 0x3A3330, "c": 0xF4F1EA, "K": 0x2B2724, "H": 0xE8D6A0, "E": 0xC9B8A8, "n": 0xFFB3C0, "k": 0x5A3A3A,
                      "e": 0x1F1A18, "G": 0x9AA3B2, "V": 0x8A7AA8, "r": 0xB98A52, "j": 0xB5793F, "B": 0xD9A85F, "b": 0x8A5A2A,
                      "S": 0xCFD3DC, "M": 0x5A2E2E, "T": 0xFF7A8A, "p": 0xFFA3B8, "X": 0xFF9F0A, "Z": 0xCFD8E0, "w": 0xFFFFFF,
                      "d": 0x7AA2FF]
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
            case .fish: colors["u"] = brand; colors["U"] = lighten(brand)
            case .pear: colors["c"] = lighten(brand); colors["s"] = brand
            case .bbq: colors["F"] = lighten(brand); colors["f"] = brand; colors["C"] = brand
            case .ox: colors["B"] = brand; colors["b"] = fade(brand, 0.6)
            }
        }
        if kind == .bit {
            let light = warning ?? (tint == .service ? brand : 0x5AD19A)
            colors["L"] = light; colors["m"] = light
        }
        if kind == .jelly || kind == .mochi, let warning { colors["f"] = warning; colors["F"] = lighten(warning) }
        if kind == .sprout, let warning { colors["m"] = warning }
        if kind == .fish, let warning { colors["u"] = warning; colors["U"] = lighten(warning) }
        if kind == .ghost {
            // The ghost fades as quota is used; the notch behind it is black, so fading is
            // blending toward black. The outline and face stay.
            let solid = 0.12 + 0.88 * min(100, max(0, remaining)) / 100
            for key in ["c", "s", "h", "p"] as [Character] { if let color = colors[key] { colors[key] = fade(color, solid) } }
        }
        for (key, value) in QuotaPetHoliday.colors { colors[key] = value }
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
