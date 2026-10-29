// SPDX-License-Identifier: GPL-3.0-only
// Tiny native adapter for Claude Code / Codex. It never stores prompts, tool input or output,
// never returns instructions, and always exits quickly so it cannot block the agent.
//
//   QuotaNotchMonitorHook <event-directory>
//       Hook mode: records only the session id, event name and time.
//   QuotaNotchMonitorHook statusline <usage-directory> [<original status line command>]
//       Status line mode: records only the five_hour / seven_day rate-limit numbers Claude Code
//       passes on stdin, then runs the user's original status line command (if any) with the
//       same input and passes its output through.
import Foundation
import Darwin

let arguments = CommandLine.arguments

/// Reads stdin to EOF, keeping at most `limit` bytes. Draining the rest keeps the writer from
/// failing with EPIPE when the input is unexpectedly large.
func readInput(limit: Int) -> (data: Data, truncated: Bool) {
    var data = Data()
    var truncated = false
    while true {
        let chunk = FileHandle.standardInput.readData(ofLength: 64 * 1024)
        if chunk.isEmpty { break }
        if data.count + chunk.count > limit { truncated = true } else { data.append(chunk) }
    }
    return (data, truncated)
}

func writePrivate(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

func safeSessionName(_ value: Any?) -> String? {
    guard let id = value as? String, !id.isEmpty, id.count <= 128,
          id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }),
          id.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
    return id
}

func runStatusLine(directory: URL, chained: String?) -> Never {
    let (input, _) = readInput(limit: 4 * 1024 * 1024)
    var summary: [String] = []
    if let root = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
       let session = safeSessionName(root["session_id"]),
       let limits = root["rate_limits"] as? [String: Any] {
        var windows: [String: Any] = [:]
        for (key, label) in [("five_hour", "5h"), ("seven_day", "7d")] {
            guard let window = limits[key] as? [String: Any],
                  let used = window["used_percentage"] as? NSNumber else { continue }
            var copy: [String: Any] = ["used_percentage": used]
            if let reset = window["resets_at"] as? NSNumber { copy["resets_at"] = reset }
            windows[key] = copy
            if (0...100).contains(used.doubleValue) { summary.append("\(label) \(Int(used.doubleValue.rounded()))%") }
        }
        if !windows.isEmpty {
            let url = directory.appendingPathComponent(session + ".json")
            let previous = (try? Data(contentsOf: url)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            // Only a change in the numbers means a new server reading; re-renders keep the old time.
            if (previous?["rate_limits"] as? NSDictionary) != (windows as NSDictionary),
               let data = try? JSONSerialization.data(withJSONObject: [
                   "observed_at": Date().timeIntervalSince1970, "rate_limits": windows], options: [.sortedKeys]) {
                try? writePrivate(data, to: url)
            }
        }
    }

    guard let chained, !chained.isEmpty else {
        if !summary.isEmpty { print(summary.joined(separator: " · ")) }
        exit(0)
    }
    signal(SIGPIPE, SIG_IGN)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", chained]
    let pipe = Pipe()
    process.standardInput = pipe
    // stdout and stderr are inherited, so Claude Code sees the original command's output.
    do { try process.run() } catch { exit(0) }
    // Claude Code cancels a status line that is still running when a newer update arrives.
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    signal(SIGTERM, SIG_IGN)
    terminate.setEventHandler { process.terminate(); exit(143) }
    terminate.resume()
    try? pipe.fileHandleForWriting.write(contentsOf: input)
    try? pipe.fileHandleForWriting.close()
    process.waitUntilExit()
    exit(process.terminationStatus)
}

if arguments.count >= 3, arguments[1] == "statusline" {
    runStatusLine(directory: URL(fileURLWithPath: arguments[2], isDirectory: true),
                  chained: arguments.count > 3 ? arguments[3] : nil)
}

guard arguments.count == 2 else { exit(0) }
let (input, truncated) = readInput(limit: 1024 * 1024)
guard !truncated,
      let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      let id = event["session_id"] as? String, UUID(uuidString: id) != nil,
      let name = event["hook_event_name"] as? String,
      ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "Interrupt", "SessionEnd"].contains(name) else { exit(0) }
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    var safe: [String: Any] = ["session_id": id, "event": name, "timestamp": ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])]
    if let turn = event["turn_id"] as? String { safe["turn_id"] = String(turn.prefix(128)) }
    let data = try JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys])
    try writePrivate(data, to: directory.appendingPathComponent(id + ".json"))
} catch { /* Monitoring failure must never block the agent. */ }
exit(0)
