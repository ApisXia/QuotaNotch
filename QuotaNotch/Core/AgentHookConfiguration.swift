// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Edits another app's JSON configuration without disturbing anything QuotaNotch does not own.
enum ConfigurationDocument {
    /// Parses `data` (nil or blank means a new, empty object), applies `edit`, and serializes
    /// with the file's own indentation and trailing newline. An edit that changes nothing returns
    /// `data` untouched (empty for a missing file), so callers can skip the write.
    static func editing(_ data: Data?, _ edit: (inout OrderedJSON) throws -> Void) throws -> Data {
        let blank = data.map { String(decoding: $0, as: UTF8.self).allSatisfy(\.isWhitespace) } ?? true
        var root: OrderedJSON = .object([])
        if let data, !blank {
            do { root = try OrderedJSON.parse(data) } catch { throw CocoaError(.fileReadCorruptFile) }
            guard root.isObject else { throw CocoaError(.fileReadCorruptFile) }
        }
        let original = root
        try edit(&root)
        if root == original { return data ?? Data() }
        let indent = data.map(OrderedJSON.indentUnit(of:)) ?? "  "
        let newline = data.map { $0.last == 0x0A } ?? true
        return Data((root.serialized(indent: indent) + (newline ? "\n" : "")).utf8)
    }
}

enum AgentHookConfiguration {
    static let marker = "QuotaNotch task status"
    static let events = ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "Interrupt"]
    static let claudeEvents = ["UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func command(helper: String, eventDirectory: String) -> String {
        shellQuote(helper) + " " + shellQuote(eventDirectory)
    }

    static func updating(_ data: Data?, helper: String?, eventDirectory: String, provider: AgentProvider = .codex) throws -> Data {
        try ConfigurationDocument.editing(data) { root in
            if let hooks = root["hooks"], !hooks.isObject { throw CocoaError(.fileReadCorruptFile) }
            var eventsObject = root["hooks"] ?? .object([])
            for event in provider == .claude ? claudeEvents : events {
                if let value = eventsObject[event], value.arrayValue == nil { throw CocoaError(.fileReadCorruptFile) }
                let existing = eventsObject[event]?.arrayValue ?? []
                var groups = existing.compactMap { group -> OrderedJSON? in
                    guard let handlers = group["hooks"]?.arrayValue else { return group }
                    let remaining = handlers.filter { $0["statusMessage"]?.stringValue != marker }
                    if remaining.count == handlers.count { return group }
                    if remaining.isEmpty { return nil }
                    var copy = group
                    copy.set("hooks", .array(remaining))
                    return copy
                }
                if let helper {
                    groups.append(.object([("hooks", .array([.object([
                        ("type", .string("command")),
                        ("command", .string(command(helper: helper, eventDirectory: eventDirectory))),
                        ("timeout", .number("2")),
                        ("statusMessage", .string(marker)),
                    ])]))]))
                }
                // Leave untouched events exactly as they were, including a user's empty list.
                guard groups != existing else { continue }
                eventsObject.set(event, groups.isEmpty ? nil : .array(groups))
            }
            if case .object(let members) = eventsObject, members.isEmpty {
                root.set("hooks", nil)
            } else {
                root.set("hooks", eventsObject)
            }
        }
    }

    /// The commands of QuotaNotch's installed handlers, in file order.
    static func installedCommands(_ data: Data?) -> [String] {
        guard let data, let root = try? OrderedJSON.parse(data), case .object(let events)? = root["hooks"] else { return [] }
        return events.flatMap { event in
            (event.value.arrayValue ?? []).flatMap { group in
                (group["hooks"]?.arrayValue ?? []).compactMap { handler in
                    handler["statusMessage"]?.stringValue == marker ? handler["command"]?.stringValue : nil
                }
            }
        }
    }

    static func isInstalled(_ data: Data?) -> Bool { !installedCommands(data).isEmpty }
}

/// Writes another app's configuration file in place: keeps its permissions, refuses to clobber a
/// concurrent edit, and keeps only the very first pre-QuotaNotch copy as a backup.
enum ConfigurationFileWriter {
    enum Failure: Error, Equatable { case changedDuringEdit, tooLarge }

    static func update(_ url: URL, backup: URL?, transform: (Data?) throws -> Data) throws {
        let fm = FileManager.default
        let target = url.resolvingSymlinksInPath()
        let exists = fm.fileExists(atPath: target.path)
        let previous = exists ? try Data(contentsOf: target) : nil
        if let previous, previous.count >= 4 * 1024 * 1024 { throw Failure.tooLarge }
        let updated = try transform(previous)
        if updated == (previous ?? Data()) { return }
        if let previous, let backup, !fm.fileExists(atPath: backup.path) {
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try previous.write(to: backup, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Write beside the target, then re-check right before swapping to keep the race window tiny.
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).quotanotch-\(UUID().uuidString)")
        try updated.write(to: temporary, options: .withoutOverwriting)
        defer { try? fm.removeItem(at: temporary) }
        let current = fm.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
        guard current == previous else { throw Failure.changedDuringEdit }
        if exists {
            // Keeps the original file's permissions and other metadata.
            _ = try fm.replaceItemAt(target, withItemAt: temporary)
        } else {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            try fm.moveItem(at: temporary, to: target)
        }
    }
}
