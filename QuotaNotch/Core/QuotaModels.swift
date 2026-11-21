// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation

enum QuotaProvider: String, CaseIterable, Sendable, Identifiable {
    /// `gemini` is the Gemini quota of Google Antigravity, read through its `agy` CLI.
    case claude, codex, gemini
    var id: String { rawValue }
    var title: String {
        switch self { case .claude: return "Claude"; case .codex: return "Codex"; case .gemini: return "Gemini" }
    }
    var loginHint: String {
        switch self {
        case .claude: return "在设置 → AI 额度中连接 Claude Code，然后在 Claude Code 里发送一条消息。"
        case .codex: return "在本机终端运行 codex login，然后刷新。"
        case .gemini: return "在本机终端运行 agy 并登录，然后刷新。"
        }
    }
    /// How often to look again. Claude only reads a local file written by its status line;
    /// Gemini starts the `agy` CLI for each reading, so it is asked least often.
    var interval: TimeInterval {
        switch self { case .claude: return 30; case .codex: return 300; case .gemini: return 600 }
    }
    /// When a reading should be presented as old. Claude's numbers only change when Claude Code
    /// talks to the server, so an idle hour is normal.
    var staleAfter: TimeInterval { self == .claude ? 3 * 3600 : interval + 60 }
}

struct QuotaWindow: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let remainingPercent: Double
    let resetsAt: Date?
    /// Length of the window in seconds, when the source reports it.
    var duration: TimeInterval? = nil
    /// The reported length, or the known length of Claude's fixed windows.
    var period: TimeInterval? {
        let known: [String: TimeInterval] = ["five_hour": 5 * 3600, "seven_day": 7 * 86400]
        return duration ?? known[id]
    }
    var localizedTitle: String { Self.localized(title) }

    /// "7 天" → "7 days"; a model's week ("Fable · 7 天") keeps the model name.
    private static func localized(_ title: String) -> String {
        if let dot = title.range(of: " · ") {
            return String(title[..<dot.lowerBound]) + " · " + localized(String(title[dot.upperBound...]))
        }
        for suffix in [" 小时", " 天"] where title.hasSuffix(suffix) {
            let prefix = String(title.dropLast(suffix.count))
            if Double(prefix) != nil { return QuotaText.format("%@" + suffix, prefix) }
        }
        return QuotaText.localized(title)
    }

}

struct QuotaSnapshot: Sendable, Equatable {
    let windows: [QuotaWindow]
    let fetchedAt: Date
}

enum QuotaFailure: Error, Sendable, Equatable {
    case notSignedIn, expired, credentialsUnavailable, network, invalidResponse
    /// Claude Code's status line has not reported usage to QuotaNotch.
    case notConnected
    case http(Int)
    case rateLimited(Date)

    var message: String {
        switch self {
        case .notSignedIn: return QuotaText.localized("未找到本机 CLI 登录凭据")
        case .expired: return QuotaText.localized("登录已过期或没有用量读取权限，请重新登录")
        case .credentialsUnavailable: return QuotaText.localized("无法读取本机凭据文件，请检查文件权限")
        case .network: return QuotaText.localized("网络连接失败，稍后可重试")
        case .invalidResponse: return QuotaText.localized("用量接口没有返回可识别的数据")
        case .notConnected: return QuotaText.localized("尚未收到 Claude Code 的用量")
        case .http(let code): return QuotaText.format("用量服务暂不可用（HTTP %d）", code)
        case .rateLimited: return QuotaText.localized("服务端限流，等待重试时间")
        }
    }

    /// Failures after which an older reading must not be shown as current.
    var clearsSnapshot: Bool {
        switch self {
        case .notSignedIn, .expired, .credentialsUnavailable, .notConnected: return true
        case .network, .invalidResponse, .http, .rateLimited: return false
        }
    }
}

struct QuotaResult: Sendable, Equatable {
    var snapshot: QuotaSnapshot?
    var failure: QuotaFailure?
    var nextAttempt: Date
}

enum QuotaParser {
    static func parse(_ data: Data, provider: QuotaProvider, now: Date) throws -> QuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaFailure.invalidResponse
        }
        var windows: [QuotaWindow] = []
        if provider == .claude {
            // The `rate_limits` object Claude Code passes to its status line command.
            for (key, title) in [("five_hour", "5 小时"), ("seven_day", "7 天")] {
                guard let window = root[key] as? [String: Any],
                      let used = number(window["used_percentage"]), (0...100).contains(used) else { continue }
                var reset = number(window["resets_at"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                var remaining = 100 - used
                // The window rolled over after this reading: nothing has been used in the new one yet.
                if let date = reset, date <= now { remaining = 100; reset = nil }
                windows.append(QuotaWindow(id: key, title: title, remainingPercent: remaining, resetsAt: reset))
            }
        } else if provider == .gemini {
            windows = antigravityWindows(root)
        } else if let limits = root["rate_limit"] as? [String: Any] {
            for (key, fallback) in [("primary_window", "主窗口"), ("secondary_window", "次窗口")] {
                guard let window = limits[key] as? [String: Any],
                      let used = number(window["used_percent"]), (0...100).contains(used) else { continue }
                let seconds = number(window["limit_window_seconds"])
                let title: String
                if let seconds, seconds > 0, seconds.truncatingRemainder(dividingBy: 86400) == 0 {
                    title = "\(String(format: "%.0f", seconds / 86400)) 天"
                } else if let seconds, seconds > 0, seconds.truncatingRemainder(dividingBy: 3600) == 0 {
                    title = "\(String(format: "%.0f", seconds / 3600)) 小时"
                } else { title = fallback }
                var reset: Date?
                if let epoch = number(window["reset_at"]), epoch > 0 {
                    reset = Date(timeIntervalSince1970: epoch)
                } else if let delta = number(window["reset_after_seconds"]), delta >= 0 {
                    reset = now.addingTimeInterval(delta)
                }
                windows.append(QuotaWindow(id: key, title: title, remainingPercent: 100 - used, resetsAt: reset,
                                           duration: seconds.flatMap { $0 > 0 ? $0 : nil }))
            }
        }
        // Missing/unsupported fields are never interpreted as 0% used or unlimited.
        guard !windows.isEmpty else { throw QuotaFailure.invalidResponse }
        return QuotaSnapshot(windows: windows, fetchedAt: now)
    }

    /// The report printed by `agy -p /usage --output-format json`: groups of quota buckets, each
    /// with the fraction left. Field names follow CodexBar's parser for the same report.
    /// Gemini's own windows come first with plain titles; other pools (Claude and GPT models
    /// used through Antigravity) keep their group name, as in "Claude and GPT · 7 天".
    private static func antigravityWindows(_ root: [String: Any]) -> [QuotaWindow] {
        guard root["status"] as? String == "SUCCESS",
              let command = root["command"] as? [String: Any], command["name"] as? String == "usage",
              let data = command["data"] as? [String: Any],
              let groups = data["groups"] as? [[String: Any]] else { return [] }
        var gemini: [QuotaWindow] = []
        var others: [QuotaWindow] = []
        var seen = Set<String>()
        for group in groups {
            var label = ((group["display_name"] ?? group["name"]) as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if label.lowercased().hasSuffix(" models") { label = String(label.dropLast(7)) }
            let plain = label.isEmpty || label.lowercased() == "gemini"
            var windows: [QuotaWindow] = []
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let id = ((bucket["bucket_id"] ?? bucket["id"]) as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty, !seen.contains(id),
                      bucket["disabled"] as? Bool != true,
                      let fraction = number(bucket["remaining_fraction"])
                        ?? number((bucket["remaining"] as? [String: Any])?["remaining_fraction"]),
                      (0...1).contains(fraction) else { continue }
                seen.insert(id)
                // "5h" / "weekly", from the explicit cadence or else the bucket id ("gemini-5h").
                let cadence = ((bucket["window"] as? String) ?? id).lowercased()
                let period: (title: String, seconds: TimeInterval)?
                if cadence.hasSuffix("5h") { period = ("5 小时", 5 * 3600) }
                else if cadence.hasSuffix("weekly") { period = ("7 天", 7 * 86400) }
                else { period = nil }
                let name = period?.title ?? ((bucket["display_name"] ?? bucket["name"]) as? String ?? id)
                windows.append(QuotaWindow(id: id, title: plain ? name : label + " · " + name,
                                           remainingPercent: fraction * 100,
                                           resetsAt: isoDate(bucket["reset_time"] as? String),
                                           duration: period?.seconds))
            }
            // Shortest window first, like Claude's 5 hours before 7 days.
            windows.sort { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
            if plain { gemini += windows } else { others += windows }
        }
        return gemini + others
    }

    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue.isFinite ? n.doubleValue : nil
    }

    static func isoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
