// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AgentAttentionKind: String, CaseIterable { case running, waiting, completed, other, mixed }

struct AgentAttentionSummary: Equatable {
    var count = 0
    var running = 0
    var waiting = 0
    var unread = 0
    var kind: AgentAttentionKind = .completed
    var primaryState: AgentRunState = .unknown
    var primaryCount = 0
    var needsAction = false
    var isVisible: Bool { count > 0 }

    static func make(_ sessions: [AgentSession], acknowledged: [String: String]) -> Self {
        var result = Self()
        var kinds = Set<String>()
        var eligible: [AgentSession] = []
        for session in AgentCurrentSessions.latest(sessions) {
            let unread = session.state.isUnreadEvent && acknowledged[session.identity] != session.eventID
            guard session.state.isActive || unread else { continue }
            eligible.append(session)
            result.count += 1
            if unread { result.unread += 1 }
            switch session.state {
            case .running: result.running += 1; kinds.insert("running")
            case .waiting: result.waiting += 1; result.needsAction = true; kinds.insert("waiting")
            case .completed: kinds.insert("completed")
            case .failed: result.needsAction = true; kinds.insert("other")
            case .interrupted, .unknown: kinds.insert("other")
            }
        }
        result.kind = kinds.count > 1 ? .mixed : AgentAttentionKind(rawValue: kinds.first ?? "completed") ?? .other
        if let primary = AgentTaskOnlySummary.emphasis(eligible) {
            result.primaryState = primary.state
            result.primaryCount = eligible.filter { $0.state == primary.state }.count
        }
        return result
    }
}

extension AgentRunState {
    var isUnreadEvent: Bool { [.waiting, .completed, .failed, .interrupted].contains(self) }
}

enum AgentHistoryWindow: Int, CaseIterable {
    case oneHour = 1, fiveHours = 5, oneDay = 24
    static let defaultValue = Self.fiveHours
    var duration: TimeInterval { TimeInterval(rawValue) * 3600 }
}

/// Bounded conversation history; one current record owns each provider/session identity.
enum AgentCurrentSessions {
    static func latest(_ sessions: [AgentSession]) -> [AgentSession] {
        var unique: [String: AgentSession] = [:]
        for session in sessions {
            if let old = unique[session.identity], old.updatedAt > session.updatedAt { continue }
            unique[session.identity] = session
        }
        return unique.values.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.identity < $1.identity
        }
    }
    static func includes(_ session: AgentSession, now: Date, window: AgentHistoryWindow,
                         retained: [String: String] = [:]) -> Bool {
        session.state.isActive
            || session.updatedAt >= now.addingTimeInterval(-window.duration)
            || retained[session.identity] == session.eventID
    }
}

/// The left symbol communicates urgency; the right list independently follows recency.
enum AgentTaskOnlySummary {
    static func recent(_ sessions: [AgentSession]) -> [AgentSession] {
        Array(AgentCurrentSessions.latest(sessions).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.identity < $1.identity
        }.prefix(2))
    }
    static func emphasis(_ sessions: [AgentSession]) -> AgentSession? {
        func priority(_ state: AgentRunState) -> Int {
            switch state { case .failed: return 0; case .waiting: return 1; case .running: return 2; default: return 3 }
        }
        return AgentCurrentSessions.latest(sessions).min {
            if priority($0.state) != priority($1.state) { return priority($0.state) < priority($1.state) }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.identity < $1.identity
        }
    }
}

/// Normalized clock-based motion; no percentage or audio-level semantics.
enum AgentGlyphMotion {
    static func pageX(at elapsed: Double) -> Double { sin(max(0, elapsed) / 1.8 * 2 * .pi) * 1.6 }
    static func pageY(at elapsed: Double) -> Double { cos(max(0, elapsed) / 1.8 * 2 * .pi) * 1.4 }
    static func waitingOffset(at elapsed: Double) -> Double {
        let t = max(0, elapsed).truncatingRemainder(dividingBy: 3.6)
        if t < 0.22 { return -sin(t / 0.22 * .pi) * 1.5 }
        if t >= 0.34 && t < 0.52 { return -sin((t - 0.34) / 0.18 * .pi) * 1.1 }
        return 0
    }
    /// A soft error halo; the cross and page never change size or position.
    static func errorGlow(at elapsed: Double) -> Double {
        0.05 + 0.90 * (0.5 - 0.5 * cos(max(0, elapsed) / 3 * 2 * .pi))
    }
    static func completionSpread(at elapsed: Double) -> Double {
        let u = min(1, max(0, elapsed) / 0.35)
        return 0.65 + 1.4 * (1 - u * u * (3 - 2 * u))
    }
}
