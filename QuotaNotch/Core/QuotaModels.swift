// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation

enum QuotaProvider: String, CaseIterable, Sendable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "Codex" }
    var loginHint: String {
        self == .claude ? "在本机 Claude Code 中运行 /login，然后刷新。" : "在本机终端运行 codex login，然后刷新。"
    }
    var interval: TimeInterval { self == .claude ? 900 : 300 }
}

struct QuotaWindow: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let remainingPercent: Double
    let resetsAt: Date?
}

struct QuotaSnapshot: Sendable, Equatable {
    let windows: [QuotaWindow]
    let fetchedAt: Date
}

enum QuotaFailure: Error, Sendable, Equatable {
    case notSignedIn, expired, credentialsUnavailable, network, invalidResponse
    case http(Int)
    case rateLimited(Date)

    var message: String {
        switch self {
        case .notSignedIn: return "未找到本机 CLI 登录凭据"
        case .expired: return "登录已过期或没有用量读取权限，请重新登录"
        case .credentialsUnavailable: return "无法读取本机凭据，请检查文件或钥匙串权限"
        case .network: return "网络连接失败，稍后可重试"
        case .invalidResponse: return "用量接口没有返回可识别的数据"
        case .http(let code): return "用量服务暂不可用（HTTP \(code)）"
        case .rateLimited: return "服务端限流，等待重试时间"
        }
    }
}

struct QuotaResult: Sendable {
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
            for (key, title) in [("five_hour", "5 小时"), ("seven_day", "7 天"),
                                 ("seven_day_sonnet", "Sonnet · 7 天"), ("seven_day_opus", "Opus · 7 天")] {
                guard let window = root[key] as? [String: Any],
                      let used = number(window["utilization"]), (0...100).contains(used) else { continue }
                windows.append(QuotaWindow(id: key, title: title, remainingPercent: 100 - used,
                                           resetsAt: isoDate(window["resets_at"] as? String)))
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
                windows.append(QuotaWindow(id: key, title: title, remainingPercent: 100 - used, resetsAt: reset))
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
