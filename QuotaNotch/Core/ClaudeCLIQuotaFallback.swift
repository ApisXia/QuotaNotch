// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if os(macOS)
import Darwin
#endif

protocol ClaudeQuotaFallback: Sendable {
    func fetch(now: Date) async throws -> QuotaSnapshot
}

/// Runs only Claude Code's built-in /usage screen, never an inference prompt.
/// Used when the status line is silent or behind (see `QuotaClient.probeSpacing`).
struct ClaudeCLIQuotaFallback: ClaudeQuotaFallback {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var timeout: TimeInterval = 20

    func fetch(now: Date) async throws -> QuotaSnapshot {
        #if os(macOS)
        let cancellation = ClaudeCLICancellation()
        let result: Result<QuotaSnapshot, Error> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Result { try run(now: now, cancellation: cancellation) })
                }
            }
        } onCancel: { cancellation.cancel() }
        ClaudeUsageLog.record(result, screen: cancellation.screen, home: home)
        return try result.get()
        #else
        throw QuotaFailure.notSignedIn
        #endif
    }

    #if os(macOS)
    private func run(now: Date, cancellation: ClaudeCLICancellation) throws -> QuotaSnapshot {
        var env = environment
        // Like CodexBar's probe: the Claude.ai login only, no API keys, and no self-update.
        for name in env.keys where name == "CLAUDE_CODE_OAUTH_TOKEN" || name.hasPrefix("ANTHROPIC_") {
            env.removeValue(forKey: name)
        }
        env["DISABLE_AUTOUPDATER"] = "1"
        let directories = (env["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".npm-global/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        guard let binary = directories.filter({ $0.hasPrefix("/") })
            .map({ URL(fileURLWithPath: $0).appendingPathComponent("claude") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw QuotaFailure.notSignedIn
        }
        env["PATH"] = directories.joined(separator: ":")
        env["TERM"] = "xterm-256color"
        env["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
        // CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC must stay unset: it also stops /usage from
        // refreshing, which then shows numbers from earlier ("couldn't refresh").
        let directory = home.appendingPathComponent("Library/Application Support/QuotaNotch/ClaudeUsage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var master: Int32 = -1
        var slave: Int32 = -1
        // As tall as CodexBar's probe: rows that scroll off the top are lost from the replayed screen.
        var size = winsize(ws_row: UInt16(ClaudeUsageScreen.rows), ws_col: UInt16(ClaudeUsageScreen.columns), ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw QuotaFailure.network }
        let input = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        defer { try? input.close(); close(master) }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["/usage", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
            "--settings", "{\"disableAllHooks\":true}"]
        process.qualityOfService = .utility
        process.environment = env
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = input
        process.standardError = input
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                let end = ProcessInfo.processInfo.systemUptime + 1
                while process.isRunning && ProcessInfo.processInfo.systemUptime < end { usleep(20_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        var candidate: QuotaSnapshot?
        var settledAt = ProcessInfo.processInfo.systemUptime
        var trustKeysLeft = 4
        var lastTrustKey = -Double.infinity
        func send(_ keys: String) { _ = keys.withCString { write(master, $0, strlen($0)) } }
        while ProcessInfo.processInfo.systemUptime < deadline {
            if cancellation.isCancelled { throw CancellationError() }
            var event = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            _ = poll(&event, 1, 100)
            let count = read(master, &bytes, bytes.count)
            if count > 0 {
                let chunk = Data(bytes.prefix(count))
                output.append(chunk)
                guard output.count <= 512 * 1024 else { throw QuotaFailure.invalidResponse }
                // Claude Code asks where the cursor is and waits for the answer.
                if chunk.range(of: Data("\u{1b}[6n".utf8)) != nil { send("\u{1b}[1;1R") }
                let screen = ClaudeUsageScreen.render(String(decoding: output, as: UTF8.self))
                cancellation.screen = screen
                if let failure = ClaudeUsageScreen.failure(in: screen, now: now) { throw failure }
                // The trust question for QuotaNotch's own empty probe folder is answered "yes".
                // One key at a time, after the dialog has had time to redraw.
                if trustKeysLeft > 0, ProcessInfo.processInfo.systemUptime - lastTrustKey >= 1.5,
                   let keys = ClaudeUsageScreen.workspaceTrustKeys(onScreen: screen) {
                    send(keys); trustKeysLeft -= 1; lastTrustKey = ProcessInfo.processInfo.systemUptime
                }
                let parsed = try? ClaudeUsageScreen.parse(screen, now: now)
                if parsed != candidate { candidate = parsed; settledAt = ProcessInfo.processInfo.systemUptime }
            }
            // Rows below the session keep drawing for a moment; wait until the reading holds for 2 s.
            if let candidate, ProcessInfo.processInfo.systemUptime - settledAt >= 2 { return candidate }
            if !process.isRunning && count <= 0 { break }
        }
        if let candidate { return candidate }
        throw QuotaFailure.invalidResponse
    }
    #endif
}

private final class ClaudeCLICancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var lastScreen = ""
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
    /// The last rendered screen, for the log when a run fails.
    var screen: String {
        get { lock.lock(); defer { lock.unlock() }; return lastScreen }
        set { lock.lock(); defer { lock.unlock() }; lastScreen = newValue }
    }
}

/// One line per /usage run in ~/Library/Logs/QuotaNotch/claude-usage.log, with the screen
/// when it failed, so a silent background failure can be diagnosed. The screen shows only
/// usage numbers; nothing secret is written. The file is cut back when it grows past 256 KB.
enum ClaudeUsageLog {
    static func record(_ result: Result<QuotaSnapshot, Error>, screen: String, home: URL) {
        #if os(macOS) && !SETTINGS_PREVIEW
        let directory = home.appendingPathComponent("Library/Logs/QuotaNotch", isDirectory: true)
        let url = directory.appendingPathComponent("claude-usage.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        var entry: String
        switch result {
        case .success(let snapshot):
            entry = "\(stamp) ok " + snapshot.windows.map { "\($0.id)=\(Int($0.remainingPercent.rounded()))% left"
                + ($0.resetsAt == nil ? " (no reset)" : "") }.joined(separator: " ") + "\n"
            // A reading without reset times is kept with its screen, to see what was not understood.
            if snapshot.windows.contains(where: { $0.resetsAt == nil }) {
                entry += "--- screen ---\n\(String(screen.suffix(4000)))\n--- end ---\n"
            }
        case .failure(let error):
            entry = "\(stamp) failed \(error)\n--- screen ---\n\(String(screen.suffix(4000)))\n--- end ---\n"
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 256 * 1024 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(entry.utf8)); try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
        #endif
    }
}

enum ClaudeUsageScreen {
    static func parse(_ screen: String, now: Date) throws -> QuotaSnapshot {
        if let failure = failure(in: screen, now: now) { throw failure }
        let lower = screen.lowercased()
        guard !lower.contains("loading usage"), !lower.contains("failed to load usage") else {
            throw QuotaFailure.invalidResponse
        }
        let lines = screen.components(separatedBy: .newlines)
        let regex = try NSRegularExpression(pattern: #"(?<![\d.\-])(\d{1,3}(?:\.\d+)?)\s*%\s*(used|left|remaining)\b"#, options: .caseInsensitive)
        var windows: [String: QuotaWindow] = [:]
        for (index, line) in lines.enumerated() {
            guard let named = window(for: line) else { continue }
            let (id, title) = named
            var section = [line]
            for next in lines.dropFirst(index + 1).prefix(10) {
                if next.lowercased().contains("current ") || next.lowercased().contains("extra usage") { break }
                section.append(next)
            }
            let text = section.joined(separator: "\n")
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text), let percentage = Double(text[range]),
                  (0...100).contains(percentage), let kind = Range(match.range(at: 2), in: text) else { continue }
            let used = text[kind].lowercased() == "used"
            windows[id] = QuotaWindow(id: id, title: title, remainingPercent: used ? 100 - percentage : percentage,
                resetsAt: relativeReset(text, now: now) ?? absoluteReset(text, now: now))
        }
        guard windows["five_hour"] != nil else { throw QuotaFailure.invalidResponse }
        let order = ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus"]
        let others = windows.keys.filter { !order.contains($0) }.sorted()
        return QuotaSnapshot(windows: (order + others).compactMap { windows[$0] }, fetchedAt: now - shownAge(screen))
    }

    /// "Showing last-known usage as of 36m ago (couldn't refresh)": how old the numbers are.
    static func shownAge(_ screen: String) -> TimeInterval {
        let compact = screen.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let start = compact.range(of: "usageasof") else { return 0 }
        let tail = compact[start.upperBound...]
        guard let match = tail.range(of: #"^(\d+)([smhd])"#, options: .regularExpression),
              let number = Double(tail[match].dropLast()) else { return 0 }
        switch tail[match].last {
        case "s": return number
        case "m": return number * 60
        case "h": return number * 3600
        default: return number * 86400
        }
    }

    /// The window a section heading names: the session, the whole week, or one model's week
    /// ("Current week (Sonnet only)", "Current week (Fable)").
    private static func window(for line: String) -> (id: String, title: String)? {
        let lower = line.lowercased()
        if lower.contains("current session") { return ("five_hour", "5 小时") }
        if lower.contains("current week (all models)") { return ("seven_day", "7 天") }
        guard let open = lower.range(of: "current week ("), let close = lower[open.upperBound...].firstIndex(of: ")") else { return nil }
        let name = line[open.upperBound..<close].replacingOccurrences(of: " only", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        if name.lowercased().contains("sonnet") { return ("seven_day_sonnet", "Sonnet · 7 天") }
        if name.lowercased().contains("opus") { return ("seven_day_opus", "Opus · 7 天") }
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !key.isEmpty else { return nil }
        return ("seven_day_" + key, "\(name) · 7 天")
    }

    // Adapted from CodexBar (https://github.com/steipete/CodexBar, MIT License,
    // Copyright (c) 2026 Peter Steinberger; see THIRD_PARTY_LICENSES): the trust dialog keys,
    // and below, the screen size and the reading of reset times.

    static let rows = 200
    static let columns = 160

    /// The keys that answer the workspace trust dialog on screen, or nil when none is shown: an
    /// arrow moves the `❯` marker to "Yes, I trust this folder" and Enter follows once it is
    /// there, so Enter never confirms another option.
    static func workspaceTrustKeys(onScreen screen: String) -> String? {
        func needle(_ text: String) -> String { String(text.lowercased().filter { !$0.isWhitespace }) }
        let normalized = needle(screen)
        let lines = screen.components(separatedBy: "\n")
        guard let optionRow = lines.firstIndex(where: { needle($0).contains("yes,itrustthisfolder") }) else {
            if normalized.contains("doyoutrustthefilesinthisfolder?") { return "y\r" }
            if normalized.contains("readytocodehere?") { return "\r" }
            return nil
        }
        let isBlank = { (row: Int) in lines[row].allSatisfy(\.isWhitespace) }
        var firstRow = optionRow
        while firstRow > lines.startIndex, !isBlank(firstRow - 1) { firstRow -= 1 }
        var lastRow = optionRow
        while lastRow < lines.endIndex - 1, !isBlank(lastRow + 1) { lastRow += 1 }
        guard let markerRow = (firstRow...lastRow).first(where: { lines[$0].contains("❯") }) else { return nil }
        if markerRow == optionRow { return "\r" }
        return markerRow < optionRow ? "\u{1b}[B" : "\u{1b}[A"
    }

    /// "Resets 2:10am (Asia/Tokyo)", "Resets Nov 6 at 11pm (Asia/Tokyo)", "Resets Nov 6, 2026, 9am":
    /// the next such moment in that time zone (or the Mac's own when none is given).
    static func absoluteReset(_ text: String, now: Date) -> Date? {
        guard let line = text.components(separatedBy: .newlines).first(where: {
            $0.range(of: #"(?i)\bresets?\b(?!\s+in\b)"#, options: .regularExpression) != nil
        }), let start = line.range(of: #"(?i)\bresets?\b"#, options: .regularExpression) else { return nil }
        // The capture sometimes ends with a stray ")" or a border; keep text up to the time zone.
        var raw = String(line[start.lowerBound...]).trimmingCharacters(in: .whitespaces)
        raw = raw.replacingOccurrences(of: #"(?i)^resets?:?\s*"#, with: "", options: .regularExpression)
        var zone: TimeZone?
        if let tz = raw.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            zone = TimeZone(identifier: String(raw[tz]).trimmingCharacters(in: CharacterSet(charactersIn: "() ")))
            raw = String(raw[..<tz.lowerBound])
        }
        raw = raw.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: #"(?i)\b([A-Za-z]{3})(\d)"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #",(\d)"#, with: ", $1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)\.(\d{2})\b"#, with: ":$1", options: .regularExpression)
            .replacingOccurrences(of: #"[^A-Za-z0-9:, ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        formatter.defaultDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
        func parse(_ formats: [String]) -> Date? {
            for format in formats { formatter.dateFormat = format; if let date = formatter.date(from: raw) { return date } }
            return nil
        }
        if let date = parse(["MMM d, yyyy, h:mma", "MMM d, yyyy, h:mm a", "MMM d, yyyy h:mma", "MMM d, yyyy h:mm a",
                             "MMM d yyyy h:mma", "MMM d, yyyy, ha", "MMM d, yyyy ha", "MMM d, yyyy h a", "MMM d yyyy ha",
                             "MMM d, yyyy, HH:mm", "MMM d, yyyy HH:mm"]) { return date }
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        // A date without a year is the next one; a time alone is the next one too.
        if let date = parse(["MMM d, h:mma", "MMM d, h:mm a", "MMM d h:mma", "MMM d h:mm a", "MMM d, HH:mm", "MMM d HH:mm",
                             "MMM d, ha", "MMM d, h a", "MMM d ha", "MMM d h a"]) {
            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            parts.year = today.year
            guard let thisYear = calendar.date(from: parts) else { return nil }
            if thisYear >= now.addingTimeInterval(-60) { return thisYear }
            return calendar.date(byAdding: .year, value: 1, to: thisYear)
        }
        if let time = parse(["h:mma", "h:mm a", "HH:mm", "H:mm", "ha", "h a"]) {
            var parts = calendar.dateComponents([.hour, .minute], from: time)
            parts.year = today.year; parts.month = today.month; parts.day = today.day
            guard let sameDay = calendar.date(from: parts) else { return nil }
            if sameDay >= now.addingTimeInterval(-60) { return sameDay }
            return calendar.date(byAdding: .day, value: 1, to: sameDay)
        }
        return nil
    }

    static func failure(in screen: String, now: Date) -> QuotaFailure? {
        let lower = screen.lowercased()
        if lower.contains("rate limited") || lower.contains("rate_limit_error") || lower.contains("rate limit exceeded") ||
            lower.contains("too many requests") || lower.range(of: #"(?:error|http|status)[^\n]*\b429\b"#, options: .regularExpression) != nil {
            return .rateLimited(now.addingTimeInterval(900))
        }
        if lower.contains("not logged in") || lower.contains("please log in") || lower.contains("token_expired") ||
            lower.contains("token has expired") || lower.contains("authentication_error") { return .expired }
        return nil
    }

    private static func relativeReset(_ text: String, now: Date) -> Date? {
        guard let line = text.components(separatedBy: .newlines).first(where: { $0.lowercased().contains("resets in ") }),
              let start = line.lowercased().range(of: "resets in "),
              let regex = try? NSRegularExpression(pattern: #"(\d+)\s*([dhm])\b"#) else { return nil }
        let duration = String(line[start.upperBound...]).lowercased()
        let matches = regex.matches(in: duration, range: NSRange(duration.startIndex..., in: duration))
        var seconds: Double = 0
        for match in matches {
            guard let n = Range(match.range(at: 1), in: duration), let unit = Range(match.range(at: 2), in: duration),
                  let value = Double(duration[n]) else { continue }
            seconds += value * (duration[unit] == "d" ? 86400 : (duration[unit] == "h" ? 3600 : 60))
        }
        return matches.isEmpty ? nil : now.addingTimeInterval(seconds)
    }

    /// Minimal VT screen: apply cursor moves and erases so old quota values from redraws are not reused.
    static func render(_ raw: String) -> String {
        let rows = Self.rows, cols = Self.columns
        var cells = Array(repeating: Array(repeating: Character(" "), count: cols), count: rows)
        var row = 0, col = 0, savedRow = 0, savedCol = 0
        let input = Array(raw)
        var index = 0
        while index < input.count {
            let ch = input[index]; index += 1
            if ch == "\u{1b}", index < input.count {
                let type = input[index]; index += 1
                if type == "]" {
                    while index < input.count {
                        if input[index] == "\u{07}" { index += 1; break }
                        if input[index] == "\u{1b}", index + 1 < input.count, input[index + 1] == "\\" { index += 2; break }
                        index += 1
                    }
                } else if type == "[" {
                    var params = ""
                    while index < input.count, let code = input[index].asciiValue, !(64...126).contains(code) {
                        params.append(input[index]); index += 1
                    }
                    guard index < input.count else { break }
                    let command = input[index]; index += 1
                    let values = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                    let first = values.first ?? 0, amount = max(1, first)
                    switch command {
                    case "A": row = max(0, row - amount)
                    case "B": row = min(rows - 1, row + amount)
                    case "C": col = min(cols - 1, col + amount)
                    case "D": col = max(0, col - amount)
                    case "G": col = min(cols - 1, amount - 1)
                    case "H", "f": row = min(rows - 1, amount - 1); col = min(cols - 1, max(1, values.count > 1 ? values[1] : 1) - 1)
                    case "J":
                        for r in 0..<rows { for c in 0..<cols {
                            if first == 2 || first == 3 || (first == 0 && (r > row || (r == row && c >= col))) ||
                                (first == 1 && (r < row || (r == row && c <= col))) { cells[r][c] = " " }
                        } }
                    case "K":
                        for c in 0..<cols where first == 2 || (first == 0 && c >= col) || (first == 1 && c <= col) { cells[row][c] = " " }
                    case "s": savedRow = row; savedCol = col
                    case "u": row = savedRow; col = savedCol
                    default: break
                    }
                }
                continue
            }
            if ch == "\r" { col = 0; continue }
            if ch == "\n" || ch == "\r\n" {
                row += 1; col = 0
            } else if ch == "\u{08}" { col = max(0, col - 1) }
            else if ch == "\t" { col = min(cols - 1, (col / 8 + 1) * 8) }
            else if !ch.unicodeScalars.contains(where: { $0.value < 32 }) {
                cells[row][col] = ch; col += 1
                if col >= cols { col = 0; row += 1 }
            }
            if row >= rows { cells.removeFirst(); cells.append(Array(repeating: " ", count: cols)); row = rows - 1 }
        }
        return cells.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
