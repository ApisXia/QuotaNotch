// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Where Claude quota comes from. The default reads what Claude Code itself passes to its
/// status line command, so QuotaNotch never touches Claude Code's Keychain item or token.
protocol ClaudeUsageSource: Sendable {
    func latest(now: Date) async throws -> QuotaSnapshot
}

/// Reads the per-session records written by `QuotaNotchMonitorHook statusline`.
///
/// Each record is `{"observed_at": <epoch seconds>, "rate_limits": {...}}`. The helper only bumps
/// `observed_at` when a session's numbers change, i.e. after a real API response, so the record
/// with the newest `observed_at` is the freshest reading across all open sessions.
struct ClaudeStatusLineUsage: ClaudeUsageSource {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuotaNotch/ClaudeStatusLine", isDirectory: true)
    }
    var directory: URL
    /// Records this old are deleted; no window lasts longer than a week.
    var retention: TimeInterval = 8 * 24 * 3600

    func latest(now: Date) async throws -> QuotaSnapshot {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { throw QuotaFailure.notConnected }
        var best: (Date, Data)?
        for name in names where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), data.count < 64 * 1024,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let observed = QuotaParser.number(root["observed_at"]),
                  let limits = root["rate_limits"] as? [String: Any],
                  let encoded = try? JSONSerialization.data(withJSONObject: limits) else { continue }
            let at = Date(timeIntervalSince1970: observed)
            if now.timeIntervalSince(at) > retention { try? fm.removeItem(at: url); continue }
            if best == nil || at > best!.0 { best = (at, encoded) }
        }
        guard let best else { throw QuotaFailure.notConnected }
        let (observed, limits) = best
        let snapshot = try QuotaParser.parse(limits, provider: .claude, now: now)
        return QuotaSnapshot(windows: snapshot.windows, fetchedAt: min(observed, now))
    }
}

/// Installs QuotaNotch in Claude Code's `statusLine` setting, chaining any existing command.
///
/// Only the `command` field is replaced (padding, refreshInterval etc. are kept), and the
/// original command is carried as an argument, so removal restores the file byte for byte
/// without any separate backup.
enum ClaudeStatusLineConfiguration {
    static let mode = "statusline"

    static func command(helper: String, usageDirectory: String, chained: String?) -> String {
        var parts = [helper, mode, usageDirectory]
        if let chained, !chained.isEmpty { parts.append(chained) }
        return parts.map(AgentHookConfiguration.shellQuote).joined(separator: " ")
    }

    /// The arguments of a command QuotaNotch generated, or nil for anything else.
    static func parse(_ command: String) -> (helper: String, usageDirectory: String, chained: String?)? {
        guard let words = ShellWords.split(command), words.count == 3 || words.count == 4,
              words[1] == mode, words[0].hasSuffix("/QuotaNotchMonitorHook") else { return nil }
        return (words[0], words[2], words.count == 4 ? words[3] : nil)
    }

    static func isInstalled(_ data: Data?) -> Bool {
        guard let data, let root = try? OrderedJSON.parse(data),
              let command = root["statusLine"]?["command"]?.stringValue else { return false }
        return parse(command) != nil
    }

    static func installing(_ data: Data?, helper: String, usageDirectory: String) throws -> Data {
        try ConfigurationDocument.editing(data) { root in
            let current = root["statusLine"]
            if let current, !current.isObject { throw CocoaError(.fileReadCorruptFile) }
            let existing = current?["command"]?.stringValue
            let chained: String?
            if let existing, let ours = parse(existing) { chained = ours.chained } else { chained = existing }
            var line = current ?? .object([("type", .string("command"))])
            line.set("type", .string("command"))
            line.set("command", .string(command(helper: helper, usageDirectory: usageDirectory, chained: chained)))
            root.set("statusLine", line)
        }
    }

    static func removing(_ data: Data?) throws -> Data {
        try ConfigurationDocument.editing(data) { root in
            guard let line = root["statusLine"], let command = line["command"]?.stringValue,
                  let ours = parse(command) else { return }
            if let chained = ours.chained {
                var restored = line
                restored.set("command", .string(chained))
                root.set("statusLine", restored)
            } else {
                root.set("statusLine", nil)
            }
        }
    }
}

/// Splits the POSIX-shell words QuotaNotch writes: single-quoted segments and `\'`.
enum ShellWords {
    static func split(_ text: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quoted = false
        var iterator = text.makeIterator()
        while let c = iterator.next() {
            if quoted {
                if c == "'" { quoted = false } else { current.append(c) }
            } else if c == "'" {
                quoted = true; inWord = true
            } else if c == "\\" {
                guard let next = iterator.next() else { return nil }
                current.append(next); inWord = true
            } else if c == " " {
                if inWord { words.append(current); current = ""; inWord = false }
            } else {
                current.append(c); inWord = true
            }
        }
        guard !quoted else { return nil }
        if inWord { words.append(current) }
        return words
    }
}
