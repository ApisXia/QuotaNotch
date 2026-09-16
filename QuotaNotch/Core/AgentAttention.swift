// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AgentAttentionKind: String, CaseIterable { case running, waiting, completed, other, mixed }

struct AgentAttentionSummary: Equatable {
    var count = 0
    var running = 0
    var waiting = 0
    var unread = 0
    var kind: AgentAttentionKind = .completed
    var needsAction = false
    var isVisible: Bool { count > 0 }

    static func make(_ sessions: [AgentSession], acknowledged: [String: String]) -> Self {
        var result = Self()
        var kinds = Set<String>()
        var seen = Set<String>()
        for session in sessions where seen.insert(session.identity).inserted {
            let unread = session.state.isUnreadEvent && acknowledged[session.identity] != session.eventID
            guard session.state.isActive || unread else { continue }
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
        return result
    }
}

extension AgentRunState {
    var isUnreadEvent: Bool { [.waiting, .completed, .failed, .interrupted].contains(self) }
}
