// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AgentHookConfiguration {
    static let marker = "QuotaNotch task status"
    static let events = ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "Interrupt"]
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func updating(_ data: Data?, helper: String?, eventDirectory: String, provider: AgentProvider = .codex) throws -> Data {
        var object: [String: Any] = [:]
        if let data {
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            object = existing
        }
        if let hooks = object["hooks"], !(hooks is [String: Any]) { throw CocoaError(.fileReadCorruptFile) }
        var eventsObject = object["hooks"] as? [String: Any] ?? [:]
        for event in provider == .claude ? ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"] : events {
            if let value = eventsObject[event], !(value is [[String: Any]]) { throw CocoaError(.fileReadCorruptFile) }
            var groups = eventsObject[event] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var copy = group
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = handlers.filter { $0["statusMessage"] as? String != marker }
                if remaining.isEmpty { return nil }
                copy["hooks"] = remaining; return copy
            }
            if let helper {
                groups.append(["hooks": [["type": "command", "command": shellQuote(helper) + " " + shellQuote(eventDirectory),
                    "timeout": 2, "statusMessage": marker]]])
            }
            if groups.isEmpty { eventsObject.removeValue(forKey: event) }
            else { eventsObject[event] = groups }
        }
        object["hooks"] = eventsObject
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
