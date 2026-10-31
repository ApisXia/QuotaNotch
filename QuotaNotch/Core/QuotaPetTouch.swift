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

    var duration: TimeInterval {
        switch self {
        case .pat: return 1.3
        case .annoyed: return 0.9
        case .dizzy: return 2.2
        case .stir: return 1.1
        case .open: return 0.9
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
    enum Kind: Equatable, Sendable { case heart, note, star, anger, question, flower }
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
        }
    }

    static let palette: [UInt8: UInt32] = [
        UInt8(ascii: "H"): 0xFF8FB1, UInt8(ascii: "N"): 0x9FE8FF, UInt8(ascii: "S"): 0xFFE27A, UInt8(ascii: "A"): 0xFF5A4F,
        UInt8(ascii: "Q"): 0xFFFFFF, UInt8(ascii: "F"): 0xFFB3C8, UInt8(ascii: "Y"): 0xFFE27A
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
    var particles: [QuotaPetParticle] = []

    /// `reduceMotion` keeps faces and particles but drops hops, squashes, spins and shakes.
    static func at(_ reaction: QuotaPetReaction, pet: QuotaPetKind, elapsed e: TimeInterval,
                   reduceMotion: Bool = false, remaining: Double = 100) -> QuotaPetTouchPose {
        var pose = QuotaPetTouchPose()
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
        }
        return pose
    }
}
