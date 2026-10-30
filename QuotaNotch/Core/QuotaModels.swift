// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation

enum QuotaProvider: String, CaseIterable, Sendable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { switch self { case .claude: return "Claude"; case .codex: return "Codex" } }
    var loginHint: String {
        self == .claude ? "在设置 → AI 额度中连接 Claude Code，然后在 Claude Code 里发送一条消息。" : "在本机终端运行 codex login，然后刷新。"
    }
    /// How often to look again. Claude only reads a local file written by its status line.
    var interval: TimeInterval { self == .claude ? 30 : 300 }
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
