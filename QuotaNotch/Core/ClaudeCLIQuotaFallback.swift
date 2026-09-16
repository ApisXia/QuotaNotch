// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if os(macOS)
import Darwin
#endif

/// Runs only Claude Code's built-in /usage screen, never an inference prompt.
struct ClaudeCLIQuotaFallback: ClaudeQuotaFallback {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var timeout: TimeInterval = 20

    func fetch(now: Date) async throws -> QuotaSnapshot {
        #if os(macOS)
        let cancellation = ClaudeCLICancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try run(now: now, cancellation: cancellation) })
                }
            }
        } onCancel: { cancellation.cancel() }
        #else
        throw QuotaFailure.notSignedIn
        #endif
    }

    #if os(macOS)
    private func run(now: Date, cancellation: ClaudeCLICancellation) throws -> QuotaSnapshot {
        var env = environment
        for name in ["CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] {
            env.removeValue(forKey: name)
        }
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
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        let directory = home.appendingPathComponent("Library/Application Support/QuotaNotch/ClaudeUsage", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 80, ws_col: 180, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw QuotaFailure.network }
        let input = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        defer { try? input.close(); close(master) }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let process = Process()
        process.executableURL = binary
        process.arguments = ["/usage", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
            "--settings", "{\"disableAllHooks\":true}"]
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
        var acceptedTrust = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            if cancellation.isCancelled { throw CancellationError() }
            var event = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            _ = poll(&event, 1, 100)
            let count = read(master, &bytes, bytes.count)
            if count > 0 {
                output.append(contentsOf: bytes.prefix(count))
                guard output.count <= 512 * 1024 else { throw QuotaFailure.invalidResponse }
                let screen = ClaudeUsageScreen.render(String(decoding: output, as: UTF8.self))
                let lower = screen.lowercased()
                if lower.contains("rate limit") || lower.contains("too many requests") || lower.contains("error: 429") {
                    throw QuotaFailure.rateLimited(now.addingTimeInterval(900))
                }
                // Acknowledge only the dedicated empty probe directory's trust prompt, once.
                if !acceptedTrust && (lower.contains("yes, i trust this folder") || lower.contains("trust this workspace")) {
                    _ = "\r".withCString { write(master, $0, 1) }
                    acceptedTrust = true
                }
                let parsed = try? ClaudeUsageScreen.parse(screen, now: now)
                if parsed != candidate { candidate = parsed; settledAt = ProcessInfo.processInfo.systemUptime }
            }
            if let candidate, ProcessInfo.processInfo.systemUptime - settledAt >= 0.8 { return candidate }
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
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}

enum ClaudeUsageScreen {
    static func parse(_ screen: String, now: Date) throws -> QuotaSnapshot {
        let lower = screen.lowercased()
        guard !lower.contains("loading usage"), !lower.contains("failed to load usage") else {
            throw QuotaFailure.invalidResponse
        }
        let labels = ["current session", "current week (all models)", "current week (sonnet only)",
                      "current week (sonnet)", "current week (opus)"]
        let lines = screen.components(separatedBy: .newlines)
        let regex = try NSRegularExpression(pattern: #"(?<![\d.\-])(\d{1,3}(?:\.\d+)?)\s*%\s*(used|left|remaining)\b"#, options: .caseInsensitive)
        var windows: [String: QuotaWindow] = [:]
        for (index, line) in lines.enumerated() {
            guard let label = labels.first(where: { line.lowercased().contains($0) }) else { continue }
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
            let id = label == labels[0] ? "five_hour" : (label == labels[1] ? "seven_day" :
                (label.contains("sonnet") ? "seven_day_sonnet" : "seven_day_opus"))
            let title = id == "five_hour" ? "5 小时" : (id == "seven_day" ? "7 天" :
                (id == "seven_day_sonnet" ? "Sonnet · 7 天" : "Opus · 7 天"))
            windows[id] = QuotaWindow(id: id, title: title, remainingPercent: used ? 100 - percentage : percentage,
                resetsAt: relativeReset(text, now: now))
        }
        guard windows["five_hour"] != nil else { throw QuotaFailure.invalidResponse }
        let order = ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus"]
        return QuotaSnapshot(windows: order.compactMap { windows[$0] }, fetchedAt: now)
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
        let rows = 80, cols = 180
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
