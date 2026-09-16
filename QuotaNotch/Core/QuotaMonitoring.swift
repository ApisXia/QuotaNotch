// SPDX-License-Identifier: GPL-3.0-only
import Foundation

extension QuotaResult {
    func isStale(provider: QuotaProvider, now: Date) -> Bool {
        guard let snapshot else { return true }
        return failure != nil || now.timeIntervalSince(snapshot.fetchedAt) > provider.interval + 60
    }
}

struct QuotaAlertState: Codable {
    var cycle: Date?
    var lowSent = false
    var recoverySent = false
    var previous: Double?

    enum Event: Equatable { case low, recovered }
    mutating func observe(_ window: QuotaWindow, threshold: Double) -> [Event] {
        let newCycle = cycle != nil && window.resetsAt != nil && cycle != window.resetsAt
        let recovered = lowSent && !recoverySent && window.remainingPercent > threshold
        if newCycle { lowSent = false; recoverySent = false }
        var events: [Event] = []
        if recovered {
            events.append(.recovered)
            recoverySent = true
            // Providers without reset dates still allow a fresh low-quota episode.
            if window.resetsAt == nil { lowSent = false }
        }
        if window.remainingPercent <= threshold && !lowSent {
            events.append(.low)
            lowSent = true
            recoverySent = false
        }
        previous = window.remainingPercent
        cycle = window.resetsAt
        return events
    }
}

enum QuotaAutomaticSelection {
    static func select(candidates: [QuotaPin], results: [QuotaProvider: QuotaResult], now: Date) -> QuotaPin? {
        candidates.compactMap { pin -> (QuotaPin, Double)? in
            guard let provider = pin.provider, let result = results[provider],
                  !result.isStale(provider: provider, now: now),
                  let window = result.snapshot?.windows.first(where: { $0.id == pin.windowID }) else { return nil }
            return (pin, window.remainingPercent)
        }.min { $0.1 < $1.1 }?.0
    }
}
