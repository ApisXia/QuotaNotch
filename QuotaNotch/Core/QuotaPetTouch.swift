// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// How the pet answers a click in the opened notch (from the approved "摸摸宠物" board).
enum QuotaPetReaction: Equatable, Sendable {
    /// One click: happy, in the pet's own way.
    case pat
    /// The third click within 2.5 s: squints, shakes, an anger mark.
    case annoyed
    /// The fifth click within 2.5 s: dizzy, stars circling its head.
    case dizzy
    /// A click while it sleeps (no quota left): it opens its eyes, a question mark, and sleeps on.
    case stir
    /// A click while a task waits: the task opens and the pet hops.
    case open
    /// A task just finished: each pet's own celebration. Plays by itself, not on a click.
    case cheer
    /// Nothing is happening: a small move of its own now and then.
    case idleMove

    var duration: TimeInterval {
        switch self {
        case .pat: return 1.3
        case .annoyed: return 0.9
        case .dizzy: return 2.2
        case .stir: return 1.1
        case .open: return 0.9
        case .cheer: return 2.4
        case .idleMove: return 2.0
        }
    }
}

/// A reaction at one moment, for pets that act it out inside their own art (the fish swims
/// around its bowl, the pear lifts its mountain).
struct QuotaPetTouchMoment: Equatable, Sendable {
    let reaction: QuotaPetReaction
    let elapsed: TimeInterval
    var reduceMotion = false
}

/// Counts clicks to pick the reaction.
struct QuotaPetTouch: Sendable {
    static let window: TimeInterval = 2.5
    private var clicks: [Date] = []

    mutating func tap(at date: Date, asleep: Bool, waiting: Bool) -> QuotaPetReaction {
        clicks = clicks.filter { date.timeIntervalSince($0) < Self.window } + [date]
        if waiting { return .open }
        if asleep {
            // Three clicks wake it for real.
            guard clicks.count >= 3 else { return .stir }
            clicks = []
            return .pat
        }
        if clicks.count >= 5 { clicks = []; return .dizzy }
        return clicks.count >= 3 ? .annoyed : .pat
    }
}

/// A small sprite that floats near the pet during a reaction.
struct QuotaPetParticle: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heart, note, star, anger, question, flower
        case spark, confettiPink, confettiBlue, confettiYellow, confettiGreen, petal
        case bubbleSmall, bubbleMedium, bubbleLarge, mountain, box, crumb, drop, grass, grassHalf, grassBit
        // holiday extras
        case lantern, moon, batUp, batDown, pumpkin, snow
    }
    let kind: Kind
    /// Position of its top-left corner in the pet's sprite pixels (may lie outside the sprite).
    let x: Double
    let y: Double
    let opacity: Double

    var rows: [String] {
        switch kind {
        case .heart: return ["H.H", "HHH", ".H."]
        case .note: return ["..N", "..N", "NNN", "NN."]
        case .star: return [".S.", "SSS", ".S."]
        case .anger: return ["A.A", ".A.", "A.A"]
        case .question: return ["QQ.", "..Q", ".Q.", "...", ".Q."]
        case .flower: return [".F.", "FYF", ".F."]
        case .spark: return [".W.", "W.W", ".W."]
        case .confettiPink: return ["P"]
        case .confettiBlue: return ["B"]
        case .confettiYellow: return ["Y"]
        case .confettiGreen: return ["G"]
        case .petal: return ["F"]
        case .bubbleSmall: return [".U.", "U.U", ".U."]
        case .bubbleMedium: return [".UUU.", "U...U", "U...U", "U...U", ".UUU."]
        case .bubbleLarge: return ["..UUU..", ".U...U.", "U.....U", "U.....U", "U.....U", ".U...U.", "..UUU.."]
        case .mountain: return ["...ww...", "..rrrr..", ".rrrRrr.", "rrrrrrrr"]
        case .box: return ["XXXXX", "XXxXX"]
        case .crumb: return ["C"]
        case .drop: return ["D", "D"]
        case .grass: return [".G.G", "GGGG", ".GG."]
        case .grassHalf: return [".G.", "GGG"]
        case .grassBit: return ["G"]
        case .lantern: return [".y.", "LLL", "LyL", "LLL", ".y.", ".y."]
        case .moon: return [".mmm.", "mmm..", "mm...", "mmm..", ".mmm."]
        case .batUp: return ["b.b.b", ".bbb."]
        case .batDown: return [".....", "bbbbb", ".b.b."]
        case .pumpkin: return ["..v..", ".ooo.", "ookoo", ".ooo."]
        case .snow: return ["W"]
        }
    }

    static let palette: [UInt8: UInt32] = [
        UInt8(ascii: "H"): 0xFF8FB1, UInt8(ascii: "N"): 0x9FE8FF, UInt8(ascii: "S"): 0xFFE27A, UInt8(ascii: "A"): 0xFF5A4F,
        UInt8(ascii: "Q"): 0xFFFFFF, UInt8(ascii: "F"): 0xFFB3C8, UInt8(ascii: "Y"): 0xFFE27A,
        UInt8(ascii: "W"): 0xFFFFFF, UInt8(ascii: "P"): 0xFF8FB1, UInt8(ascii: "B"): 0x7AA2FF, UInt8(ascii: "G"): 0x6FDC8C,
        UInt8(ascii: "U"): 0xCFEAFF, UInt8(ascii: "w"): 0xF2F4F8, UInt8(ascii: "r"): 0x8A8F99, UInt8(ascii: "R"): 0x6C717B,
        UInt8(ascii: "X"): 0xD9A85F, UInt8(ascii: "x"): 0x8A5A2A, UInt8(ascii: "C"): 0xFFB3C0, UInt8(ascii: "D"): 0x7AA2FF,
        UInt8(ascii: "L"): 0xE8443A, UInt8(ascii: "y"): 0xFFD34D, UInt8(ascii: "m"): 0xFFE27A, UInt8(ascii: "b"): 0x6B4FA0,
        UInt8(ascii: "o"): 0xFF9A2A, UInt8(ascii: "k"): 0x3A2414, UInt8(ascii: "v"): 0x5AA14A
    ]

    var sprite: QuotaPetSprite {
        let width = rows.first?.utf8.count ?? 0
        return QuotaPetSprite(width: width, height: rows.count, codes: rows.flatMap { Array($0.utf8) })
    }
}

/// The pet's look at one moment of a reaction. Distances are in sprite pixels.
struct QuotaPetTouchPose: Equatable, Sendable {
    /// The face to show, or nil for the pet's own mood.
    var mood: QuotaPetMood?
    var dx: Double = 0
    var dy: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    /// Degrees, around the pet's feet.
    var rotation: Double = 0
    var flipped = false
    var brightness: Double = 0
    var opacity: Double = 1
    /// Spins around the pet's middle instead of its feet.
    var pivotCenter = false
    var particles: [QuotaPetParticle] = []

    /// `reduceMotion` keeps faces and particles but drops hops, squashes, spins and shakes.
    static func at(_ reaction: QuotaPetReaction, pet: QuotaPetKind, elapsed e: TimeInterval,
                   reduceMotion: Bool = false, remaining: Double = 100) -> QuotaPetTouchPose {
        var pose = QuotaPetTouchPose()
        if reaction == .cheer || reaction == .idleMove {
            pose = motion(reaction, pet: pet, elapsed: e, remaining: remaining)
            pose.particles = pose.particles.map { .init(kind: $0.kind, x: $0.x, y: $0.y, opacity: max(0, min(1, $0.opacity))) }
            if reduceMotion {
                pose.dx = 0; pose.dy = 0; pose.scaleX = 1; pose.scaleY = 1; pose.rotation = 0; pose.flipped = false; pose.opacity = 1
            }
            return pose
        }
        if [.fish, .pear, .bbq, .ox].contains(pet) {
            pose = inArt(reaction, pet: pet, elapsed: e, remaining: remaining)
            pose.particles = pose.particles.map { .init(kind: $0.kind, x: $0.x, y: $0.y, opacity: max(0, min(1, $0.opacity))) }
            if reduceMotion { pose.dx = 0; pose.dy = 0; pose.rotation = 0; pose.flipped = false }
            return pose
        }
        let hop: Double = e < 0.15 ? -2 : e < 0.3 ? -3 : e < 0.45 ? -1 : e < 0.6 ? 0 : e < 0.7 ? -1 : 0
        func alternate(_ period: Double) -> Double { Int(e / period) % 2 == 0 ? -1 : 1 }
        switch reaction {
        case .pat:
            pose.mood = .celebrate
            let rise = e / reaction.duration
            switch pet {
            case .mochi:
                pose.dx = e < 0.5 ? alternate(0.1) : 0
                pose.dy = hop
                pose.particles = [.init(kind: .heart, x: 15, y: 1 - rise * 6, opacity: 1.2 - rise),
                                  .init(kind: .heart, x: 2, y: 3 - rise * 7, opacity: 1 - rise)]
            case .bit:
                pose.dy = hop
                pose.brightness = e < 0.6 && Int(e / 0.15) % 2 == 0 ? 0.25 : 0
                pose.particles = [.init(kind: .note, x: 16, y: 2 - rise * 6, opacity: 1.2 - rise),
                                  .init(kind: .note, x: 1, y: 4 - rise * 7, opacity: 1 - rise)]
            case .jelly:
                let steps: [(TimeInterval, Double, Double)] = [(0.12, 1.18, 0.8), (0.26, 0.9, 1.12), (0.4, 1.08, 0.94), (0.52, 0.96, 1.03)]
                if let step = steps.first(where: { e < $0.0 }) { pose.scaleX = step.1; pose.scaleY = step.2 }
                pose.particles = [.init(kind: .heart, x: 16, y: 1 - rise * 6, opacity: 1.2 - rise),
                                  .init(kind: .heart, x: 1, y: 3 - rise * 7, opacity: 1 - rise)]
            case .ghost:
                pose.flipped = e < 0.2 || (e >= 0.4 && e < 0.6)
                pose.dy = -(2 * sin(min(1, e / reaction.duration) * .pi)).rounded()
                pose.particles = [.init(kind: .star, x: 0, y: 2 - rise * 5, opacity: 1.2 - rise),
                                  .init(kind: .star, x: 17, y: 5 - rise * 6, opacity: 1 - rise),
                                  .init(kind: .star, x: 15, y: -rise * 4, opacity: 1.1 - rise)]
            case .sprout:
                pose.rotation = e < 0.9 ? 4 * alternate(0.13) : 0
                pose.particles = [.init(kind: .flower, x: 8.5, y: -1 - rise * 2, opacity: min(1, e / 0.2))]
            case .fish, .pear, .bbq, .ox:
                break // handled by inArt
            }
        case .annoyed:
            pose.mood = .low
            pose.dx = e < 0.6 ? alternate(0.06) : 0
            pose.particles = [.init(kind: .anger, x: 16, y: 0, opacity: Int(e / 0.15) % 2 == 0 ? 0.4 : 1)]
        case .dizzy:
            pose.mood = .low
            pose.rotation = sin(e / 0.14) * 6
            pose.particles = (0..<3).map { k in
                let angle = e / 0.26 + Double(k) * 2 * .pi / 3
                return .init(kind: .star, x: 8.5 + 8 * cos(angle), y: 0.5 + 1.6 * sin(angle), opacity: 1)
            }
        case .stir:
            if e < 0.75 {
                pose.mood = .low
                pose.particles = [.init(kind: .question, x: 16, y: 0, opacity: 1)]
            }
        case .open:
            pose.mood = .needsYou
            pose.dy = hop
        case .cheer, .idleMove:
            break // see motion
        }
        pose.particles = pose.particles.map { .init(kind: $0.kind, x: $0.x, y: $0.y, opacity: max(0, min(1, $0.opacity))) }
        if reduceMotion {
            pose.dx = 0; pose.dy = 0; pose.scaleX = 1; pose.scaleY = 1; pose.rotation = 0; pose.flipped = false
        }
        return pose
    }

    /// The fish and the pear draw their faces and moves into the art (see
    /// `QuotaPetArt.sprite(touch:)`); this adds the shake, tilt, hop and particles around them.
    private static func inArt(_ reaction: QuotaPetReaction, pet: QuotaPetKind, elapsed e: TimeInterval,
                              remaining: Double) -> QuotaPetTouchPose {
        var pose = QuotaPetTouchPose()
        let rise = e / reaction.duration
        func alternate(_ period: Double) -> Double { Int(e / period) % 2 == 0 ? -1 : 1 }
        func stars(_ y: Double) -> [QuotaPetParticle] {
            (0..<3).map { k in
                let angle = e / 0.26 + Double(k) * 2 * .pi / 3
                return .init(kind: .star, x: 8.5 + 8 * cos(angle), y: y + 1.6 * sin(angle), opacity: 1)
            }
        }
        if pet == .bbq || pet == .ox { return sausageOrCow(reaction, pet: pet, elapsed: e) }
        let fish = pet == .fish
        switch reaction {
        case .pat:
            if fish {
                // a knock on the glass
                pose.dx = e < 0.36 ? alternate(0.09) : 0
                pose.particles = [.init(kind: .heart, x: 15, y: 1 - rise * 5, opacity: 1.2 - rise),
                                  .init(kind: .heart, x: 2, y: 2 - rise * 6, opacity: 1 - rise)]
            } else {
                if QuotaPetArt.pearPressure(mood: .idle, remaining: remaining) == 0 { pose.dy = Double(QuotaPetArt.hop(e)) }
                pose.particles = [.init(kind: .heart, x: 16, y: 3 - rise * 5, opacity: 1.2 - rise),
                                  .init(kind: .note, x: 1, y: 5 - rise * 6, opacity: 1 - rise)]
            }
        case .annoyed:
            pose.dx = e < 0.6 ? alternate(0.06) : 0
            pose.particles = [.init(kind: .anger, x: 16, y: fish ? 0 : 2, opacity: Int(e / 0.15) % 2 == 0 ? 0.4 : 1)]
        case .dizzy:
            pose.rotation = sin(e / 0.14) * (fish ? 5 : 6)
            pose.particles = stars(fish || QuotaPetArt.pearPressure(mood: .idle, remaining: remaining) > 0 ? 0.5 : 2)
        case .stir:
            if e < 0.75 { pose.particles = [.init(kind: .question, x: 16, y: fish ? 1 : 3, opacity: 1)] }
        case .open:
            if !fish { pose.dy = Double(QuotaPetArt.hop(e)) }
        case .cheer, .idleMove:
            break // see motion
        }
        return pose
    }

    /// 芭比Q了 flips over when petted and spins on its skewer when dizzy; 牛马 flaps its ears and moos.
    private static func sausageOrCow(_ reaction: QuotaPetReaction, pet: QuotaPetKind, elapsed e: TimeInterval) -> QuotaPetTouchPose {
        var pose = QuotaPetTouchPose()
        let rise = e / reaction.duration
        let sausage = pet == .bbq
        func alternate(_ period: Double) -> Double { Int(e / period) % 2 == 0 ? -1 : 1 }
        switch reaction {
        case .pat:
            if sausage {
                pose.dy = Double(QuotaPetArt.hop(e))
                pose.flipped = e > 0.4
                pose.particles = [.init(kind: .heart, x: 15, y: 2 - rise * 5, opacity: 1.2 - rise),
                                  .init(kind: .heart, x: 1, y: 4 - rise * 6, opacity: 1 - rise)]
            } else {
                pose.particles = [.init(kind: .heart, x: 13, y: -rise * 3, opacity: 1.2 - rise),
                                  .init(kind: .heart, x: 0, y: 1 - rise * 4, opacity: 1 - rise)]
            }
        case .annoyed:
            pose.dx = e < 0.6 ? alternate(0.06) : 0
            pose.particles = [.init(kind: .anger, x: sausage ? 1 : 11, y: sausage ? 1 : 0, opacity: Int(e / 0.15) % 2 == 0 ? 0.4 : 1)]
        case .dizzy:
            pose.particles = (0..<3).map { k in
                let angle = e / 0.26 + Double(k) * 2 * .pi / 3
                return sausage ? .init(kind: .star, x: 8.5 + 8 * cos(angle), y: -0.5 + 1.6 * sin(angle), opacity: 1)
                               : .init(kind: .star, x: 4 + 4.8 * cos(angle), y: 1 + 1.6 * sin(angle), opacity: 1)
            }
        case .stir:
            if e < 0.75 { pose.particles = [.init(kind: .question, x: sausage ? 15 : 11, y: 1, opacity: 1)] }
        case .open:
            if sausage { pose.dy = Double(QuotaPetArt.hop(e)) }
            else { pose.particles = [.init(kind: .note, x: 11, y: 2 - rise * 4, opacity: 1.3 - rise)] }
        case .cheer, .idleMove:
            break // see motion
        }
        return pose
    }

    /// A finished task's celebration and the small moves made while nothing happens. The art
    /// changes (a tick on Bit's screen, a bite out of the sausage) are in `QuotaPetArt.sprite(touch:)`.
    private static func motion(_ reaction: QuotaPetReaction, pet: QuotaPetKind, elapsed e: TimeInterval,
                               remaining: Double) -> QuotaPetTouchPose {
        var pose = QuotaPetTouchPose()
        typealias Kind = QuotaPetParticle.Kind
        func p(_ kind: Kind, _ x: Double, _ y: Double, _ opacity: Double = 1) -> QuotaPetParticle {
            .init(kind: kind, x: x, y: y, opacity: opacity)
        }
        /// Progress 0...1 of a span that starts at `start`, or nil outside it.
        func span(_ start: Double, _ length: Double) -> Double? {
            let t = (e - start) / length
            return t < 0 || t > 1 ? nil : t
        }
        if reaction == .cheer {
            switch pet {
            case .mochi:
                // the tea's steam rises as little hearts
                pose.dy = e < 0.7 ? Double(QuotaPetArt.hop(e)) : 0
                pose.particles = (0..<3).compactMap { k in
                    span(Double(k) * 0.45, 1.4).map { t in p(.heart, 15.5 + sin(t * 6) * 0.8, 6 - t * 8, 1.4 - t) }
                }
            case .bit:
                // confetti; the tick is drawn on its screen
                let kinds: [Kind] = [.confettiPink, .confettiBlue, .confettiYellow, .confettiGreen]
                pose.particles = (0..<8).compactMap { k in
                    let t = e / 1.8 - Double(k) * 0.05
                    guard t > 0, t < 1 else { return nil }
                    return p(kinds[k % 4], 1 + Double(k) * 2.4, -1 + t * 14 + sin(Double(k) + t * 8) * 0.5, 1.3 - t)
                }
            case .jelly:
                // a big bounce: squash, stretch, squash, and stars on landing
                if e < 0.15 { pose.scaleX = 1.15; pose.scaleY = 0.85 }
                else if e < 0.65 { pose.dy = -(5 * sin(.pi * (e - 0.15) / 0.5)).rounded(); pose.scaleX = 0.92; pose.scaleY = 1.1 }
                else if e < 0.8 { pose.scaleX = 1.18; pose.scaleY = 0.82 }
                else if e < 0.95 { pose.scaleX = 0.95; pose.scaleY = 1.05 }
                if e > 0.65 && e < 1.5 {
                    let r = 2 + (e - 0.65) / 0.09
                    pose.particles = (0..<6).map { k in
                        let a = Double(k) * .pi / 3
                        return p(.star, 8.5 + cos(a) * r, 8 + sin(a) * r * 0.6, 1.6 - (e - 0.65) / 0.6)
                    }
                }
            case .ghost:
                // a loop in the air with a trail of sparkles
                let t = min(1, e / 0.9)
                if e < 0.9 { pose.rotation = t * 360; pose.pivotCenter = true; pose.dy = -(3 * sin(.pi * t)).rounded() }
                pose.particles = (0..<4).compactMap { k in
                    let tt = t - Double(k) * 0.12
                    guard tt > 0 else { return nil }
                    return p(.spark, 9 + 8 * cos(tt * 6.28 + 1.6), 7 + 6 * sin(tt * 6.28 + 1.6), 1.4 - e / 1.5)
                }
            case .sprout:
                // it blooms, and petals drift down
                pose.mood = e < 0.35 ? .idle : .celebrate
                if e > 0.35 && e < 0.65 { pose.scaleY = 1.06 }
                pose.particles = (0..<7).compactMap { k in
                    span(0.35, 1.5).map { t in
                        let a = Double(k) * 0.9 + t * 2
                        return p(.petal, 9.5 + cos(a) * (2 + t * 7), 1 + sin(a) * 2 + t * 6, 1.2 - t)
                    }
                }
            case .fish:
                // one big bubble that grows, rises and pops
                if e < 1.4 {
                    let (kind, off): (Kind, Double) = e < 0.45 ? (.bubbleSmall, 1) : e < 0.9 ? (.bubbleMedium, 2) : (.bubbleLarge, 3)
                    pose.particles = [p(kind, 14 - off, 8 - off - e / 0.3)]
                } else if let t = span(1.4, 0.6) {
                    pose.particles = (0..<6).map { k in
                        let a = Double(k) * .pi / 3
                        return p(.spark, 13 + cos(a) * (1 + t * 4), 3 + sin(a) * (1 + t * 3), 1.2 - t)
                    }
                }
            case .pear:
                // throws the mountain away and grows a leaf
                pose.mood = e < 0.3 ? .idle : .celebrate
                if e >= 0.3 { pose.dy = Double(QuotaPetArt.hop(e - 0.3)) }
                if let t = span(0.3, 1.2) { pose.particles = [p(.mountain, 6 + t * 16, -10 * t + 5.6 * t * t - 2, 1.3 - t)] }
            case .bbq:
                // someone takes a bite: crumbs and a heart
                pose.dy = e > 0.5 && e < 0.7 ? -1 : 0
                if let t = span(0.5, 1.1) {
                    pose.particles = (0..<4).map { k in p(.crumb, 13 + Double(k) * 0.7, 3 + t * 9 * (0.5 + Double(k) * 0.2), 1.3 - t) }
                }
                if e > 0.7 { pose.particles.append(p(.heart, 15, 3 - (e - 0.7) / 0.4, 1.5 - (e - 0.7) / 1.2)) }
            case .ox:
                // unloads: the boxes slide off the cart
                pose.mood = e < 0.3 ? .idle : .celebrate
                if let t = span(0.3, 1.4) {
                    pose.particles = (0..<4).compactMap { k in
                        let tt = t - Double(k) * 0.08
                        guard tt > 0 else { return nil }
                        return p(.box, 14 + tt * 9 + Double(k) * 0.5, 12 - Double(k) * 2 + tt * tt * 14 - tt * 4, 1.4 - tt)
                    }
                }
            }
        } else {
            switch pet {
            case .mochi:
                // eyes closed (in the art), a long stretch
                let s = e > 0.2 && e < 1.4 ? 1 + 0.08 * sin(.pi * (e - 0.2) / 1.2) : 1
                pose.scaleY = s; pose.scaleX = 2 - s
                if let t = span(0.3, 1.1) { pose.particles = [p(.spark, 3, 1 - t * 2.2, 1 - t)] }
            case .jelly:
                if e < 1.3 {
                    let a = sin(e / 0.07) * max(0, 1 - e / 1.3)
                    pose.scaleX = 1 + 0.08 * a; pose.scaleY = 1 - 0.08 * a
                }
            case .ghost:
                // fades out, then peeks back
                pose.opacity = e < 0.5 ? 1 - e / 0.5 * 0.85 : e < 1.3 ? 0.15 : min(1, 0.15 + (e - 1.3) / 0.6 * 0.85)
                pose.flipped = e > 1.3 && e < 1.6
                if e > 0.6 && e < 1.3 { pose.particles = [p(.spark, 16, 3, 0.7)] }
            case .sprout:
                // a drop of water lands on a leaf (the happy face is in the art)
                if e < 0.6 { pose.particles = [p(.drop, 4, -2 + e / 0.075)] }
                else if e < 1 { pose.particles = [p(.confettiBlue, 2.5, 2.5 + (e - 0.6) / 0.2), p(.confettiBlue, 5.5, 2.5 + (e - 0.6) / 0.2)] }
                if e > 0.6 && e < 0.8 { pose.scaleY = 0.96 }
            case .pear:
                // lifts the mountain off its head (in the art) and flicks off sweat
                if let t = span(0.3, 0.7) { pose.particles = [p(.drop, 16 + t * 4.7, 7 + pow(t * 4.7, 2) * 0.3)] }
            case .ox:
                // chews some grass
                pose.dy = Int(e / 0.2) % 2 == 1 && e < 1.4 ? 1 : 0
                if e < 0.5 { pose.particles = [p(.grass, 5.5, 11)] }
                else if e < 1 { pose.particles = [p(.grassHalf, 5.5, 10)] }
                else if e < 1.4 { pose.particles = [p(.grassBit, 5.5, 10)] }
            case .bit, .fish, .bbq:
                break // all in the art
            }
        }
        return pose
    }
}

/// When the pet acts by itself: its celebration right after a task finishes, and a small move
/// now and then while nothing is happening.
enum QuotaPetMotion {
    /// How often an idle pet makes a small move.
    static let idleEvery: TimeInterval = 45

    static func moment(mood: QuotaPetMood, completedAt: Date?, at date: Date, offset: TimeInterval = 0) -> QuotaPetTouchMoment? {
        if mood == .celebrate, let completedAt {
            let e = date.timeIntervalSince(completedAt)
            if e >= 0 && e < QuotaPetReaction.cheer.duration { return .init(reaction: .cheer, elapsed: e) }
        }
        if mood == .idle {
            let t = phase(date, offset)
            if t < QuotaPetReaction.idleMove.duration { return .init(reaction: .idleMove, elapsed: t) }
        }
        return nil
    }

    /// The next redraw while acting (every frame), or the start of the next idle move.
    static func nextFrame(after date: Date, mood: QuotaPetMood, completedAt: Date?, offset: TimeInterval = 0) -> Date? {
        if moment(mood: mood, completedAt: completedAt, at: date, offset: offset) != nil { return date.addingTimeInterval(1.0 / 30) }
        if mood == .idle { return date.addingTimeInterval(idleEvery - phase(date, offset) + 0.001) }
        return nil
    }

    private static func phase(_ date: Date, _ offset: TimeInterval) -> TimeInterval {
        let t = (date.timeIntervalSinceReferenceDate + offset).truncatingRemainder(dividingBy: idleEvery)
        return t < 0 ? t + idleEvery : t
    }
}
