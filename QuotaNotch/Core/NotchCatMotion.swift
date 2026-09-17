// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum CatSide: String, CaseIterable { case left, right }
enum CatAction: String, CaseIterable { case curious, rest, completed, attention }

struct CatWingSpace: Equatable {
    let occupied: CGFloat
    let limit: CGFloat
    var height: CGFloat = 32
    var room: CGFloat { max(0, limit - occupied) }
    var canPeek: Bool { room >= 16 && height >= 24 }
    var isEmpty: Bool { occupied < 0.5 }
    var canShowBody: Bool { isEmpty && room >= 30 && height >= 26 }
    var excursion: CGFloat { canPeek ? min(room, isEmpty ? 32 : 24) : 0 }
    func scale(body: Bool, backing: CGFloat) -> CGFloat {
        let fit = min(1, min(room / (body ? 30 : 24), (height - 4) / (body ? 22 : 18)))
        return max(0, floor(fit * max(1, backing)) / max(1, backing))
    }
}

struct CatPose: Equatable {
    var side: CatSide = .right
    var action: CatAction = .curious
    var elapsed: Double = 0
    var active = false
    var fullBody = false
    var frame: String? = nil
    var width: CGFloat? = nil
    var scale: CGFloat = 1
    var concealed = false
    var clip: CatClip { fullBody ? CatClips.body : CatClips.head(action) }
    var asset: String { frame ?? clip.step(at: elapsed).asset }
    var reservedWidth: CGFloat { active ? (width ?? clip.step(at: elapsed).travel * scale) : 0 }
    var extensionAmount: Double { Double(reservedWidth / (fullBody ? 30 : 24)) }
}

/// Events retain their original age and identity; duplicate arrivals cannot renew a cue.
struct CatCue: Equatable {
    let sessionID: String
    let eventID: String
    let action: CatAction
    let occurredAt: Date
}
struct CatCueQueue {
    private(set) var pending: [CatCue] = []
    private var completedShown = Date.distantPast
    private var attentionShown = Date.distantPast
    mutating func clear() { pending.removeAll() }
    mutating func enqueue(_ cue: CatCue, now: Date) {
        guard cue.action == .completed || cue.action == .attention,
              now.timeIntervalSince(cue.occurredAt) >= -2,
              now.timeIntervalSince(cue.occurredAt) <= 15,
              !pending.contains(where: { $0.eventID == cue.eventID }) else { return }
        pending.removeAll { $0.sessionID == cue.sessionID }
        pending.append(cue)
        if pending.count > 32 { pending.removeFirst(pending.count - 32) }
    }
    mutating func take(now: Date, valid: (CatCue) -> Bool) -> CatCue? {
        pending.removeAll { now.timeIntervalSince($0.occurredAt) > 15 || !valid($0) }
        let ordered = pending.sorted {
            if $0.action != $1.action { return $0.action == .attention }
            return $0.occurredAt > $1.occurredAt
        }
        guard let cue = ordered.first(where: {
            now.timeIntervalSince($0.action == .attention ? attentionShown : completedShown) >= 30
        }) else { return nil }
        // Consume the burst as one reaction; an attention reaction also supersedes completions.
        pending.removeAll { cue.action == .attention || $0.action == .completed }
        if cue.action == .attention { attentionShown = now } else { completedShown = now }
        return cue
    }
}
