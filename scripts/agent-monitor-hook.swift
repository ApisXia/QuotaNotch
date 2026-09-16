// SPDX-License-Identifier: GPL-3.0-only
// Tiny native lifecycle adapter. It never reads/writes agent prompts or returns instructions.
import Foundation
import Darwin

guard CommandLine.arguments.count == 2 else { exit(0) }
let input = FileHandle.standardInput.readData(ofLength: 1024 * 1024)
guard input.count < 1024 * 1024,
      let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      let id = event["session_id"] as? String, UUID(uuidString: id) != nil,
      let name = event["hook_event_name"] as? String,
      ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "Interrupt"].contains(name) else { exit(0) }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var safe: [String: Any] = ["session_id": id, "event": name, "timestamp": ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])]
    if let turn = event["turn_id"] as? String { safe["turn_id"] = String(turn.prefix(128)) }
    let data = try JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys])
    let url = directory.appendingPathComponent(id + ".json")
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
} catch { /* Monitoring failure must never block Codex. */ }
exit(0)
