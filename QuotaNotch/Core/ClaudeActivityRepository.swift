// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Reads Claude Code sessions when their transcripts are available locally.
/// Chat/Cowork are deliberately not inferred from Code activity.
actor ClaudeActivityRepository {
    let home: URL
    let hooks: URL
    private var entries: [URL] = []
    private var discoveryTruncated = false
    private var discovered = Date.distantPast
    private var cursors: [String: AgentLogCursor] = [:]
    private var cache: [String: AgentSession] = [:]
    private var inodes: [String: UInt64] = [:]
    /// Finished results and the hook-file time they were built from, so unchanged
    /// transcripts are not reopened (and their repository root not re-resolved) every poll.
    private var processed: [String: AgentSession] = [:]
    private var hookStamps: [String: Date] = [:]
    init(home: URL, hooks: URL) { self.home = home; self.hooks = hooks }

    func scan(now: Date = Date(), force: Bool = false) -> AgentActivitySnapshot {
        let fm = FileManager.default
        let root = home.appendingPathComponent("projects")
        var result = AgentActivitySnapshot(hasSessionDirectory: fm.fileExists(atPath: root.path))
        if force || now.timeIntervalSince(discovered) > 8 {
            entries = []; discoveryTruncated = false
            if let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in walk {
                    if url.lastPathComponent == "subagents" { walk.skipDescendants(); continue }
                    guard url.pathExtension == "jsonl", let changed = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                          now.timeIntervalSince(changed) < 7 * 86400 else { continue }
                    entries.append(url)
                    if entries.count >= 2000 { discoveryTruncated = true; break }
                }
            }
            let paths = Set(entries.map(\.path))
            cache = cache.filter { paths.contains($0.key) }
            cursors = cursors.filter { paths.contains($0.key) }
            inodes = inodes.filter { paths.contains($0.key) }
            processed = processed.filter { paths.contains($0.key) }
            hookStamps = hookStamps.filter { paths.contains($0.key) }
            discovered = now
        }
        result.truncated = discoveryTruncated
        var unique: [String: AgentSession] = [:]
        for url in entries {
            do {
                let attrs = try fm.attributesOfItem(atPath: url.path)
                let size = attrs[.size] as? UInt64 ?? 0, inode = attrs[.systemFileNumber] as? UInt64 ?? 0
                let hookID = cache[url.path]?.id ?? url.deletingPathExtension().lastPathComponent
                let hookURL = hooks.appendingPathComponent(hookID + ".json")
                let hookStamp = (try? fm.attributesOfItem(atPath: hookURL.path)[.modificationDate]) as? Date ?? .distantPast
                if !force, inodes[url.path] == inode, cursors[url.path]?.offset == size,
                   hookStamps[url.path] == hookStamp, var done = processed[url.path] {
                    guard !done.excluded, done.updatedAt != .distantPast else { continue }
                    if done.state == .running && now.timeIntervalSince(done.updatedAt) > 12 * 3600 { done.state = .unknown }
                    if unique[done.id].map({ $0.updatedAt > done.updatedAt }) != true { unique[done.id] = done }
                    continue
                }
                var cursor = cursors[url.path] ?? AgentLogCursor()
                var session = cache[url.path] ?? AgentSession(id: url.deletingPathExtension().lastPathComponent)
                session.provider = .claude; session.rolloutPath = url.path
                if inodes[url.path] != inode || size < cursor.offset {
                    cursor = AgentLogCursor(); session = AgentSession(id: session.id); session.provider = .claude; session.rolloutPath = url.path
                }
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                if cursor.offset == 0 && size > 2 * 1024 * 1024 {
                    let head = try file.read(upToCount: 65536) ?? Data()
                    var headCursor = AgentLogCursor(); headCursor.consume(head) { ClaudeActivityParser.apply($0, to: &session) }
                    session.state = .unknown; session.turnID = ""; session.waitingCallID = nil
                    session.updatedAt = .distantPast; session.startedAt = nil; session.finishedAt = nil
                    session.userPrompt = ""; session.activityDetail = ""; session.tool = ""; session.toolCallID = ""; session.toolIsRunning = false; session.attentionRevision = ""
                    cursor.offset = size - 2 * 1024 * 1024; cursor.skipping = true
                }
                try file.seek(toOffset: cursor.offset)
                cursor.consume(try file.read(upToCount: 2 * 1024 * 1024) ?? Data()) { ClaudeActivityParser.apply($0, to: &session) }
                if let attributes = try? fm.attributesOfItem(atPath: hooks.appendingPathComponent(session.id + ".json").path),
                   (attributes[.size] as? NSNumber)?.intValue ?? .max < 16384,
                   let data = try? Data(contentsOf: hooks.appendingPathComponent(session.id + ".json")),
                   let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    ClaudeActivityParser.applyHook(event, to: &session)
                }
                cursors[url.path] = cursor; cache[url.path] = session; inodes[url.path] = inode
                hookStamps[url.path] = hookStamp
                processed[url.path] = session
                guard !session.excluded, session.updatedAt != .distantPast else { continue }
                if session.state == .running && now.timeIntervalSince(session.updatedAt) > 12 * 3600 { session.state = .unknown }

                session.projectRoot = AgentProjectResolver.repositoryRoot(for: session.cwd)
                session.projectName = URL(fileURLWithPath: session.projectRoot).lastPathComponent
                if session.projectName.isEmpty { session.projectName = "Claude Code" }
                if session.title.isEmpty { session.title = String(session.userPrompt.prefix(120)) }
                processed[url.path] = session
                if unique[session.id].map({ $0.updatedAt > session.updatedAt }) != true { unique[session.id] = session }
            } catch { result.issue = "Some Claude Code task records could not be read. Retrying automatically." }
        }
        result.sessions = Array(unique.values)
        return result
    }
}

enum ClaudeActivityParser {
    static func apply(_ data: Data, to session: inout AgentSession) {
        guard let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = row["type"] as? String else { return }
        session.provider = .claude
        if let id = row["sessionId"] as? String { session.id = id }
        // Subagent transcripts are hidden, but a stray sidechain row must not hide a main session.
        if row["isSidechain"] as? Bool == true {
            if session.updatedAt == .distantPast { session.excluded = true }
            return
        }
        session.excluded = false
        if let cwd = row["cwd"] as? String { session.cwd = cwd }
        let entry = (row["entrypoint"] as? String ?? "").lowercased()
        if entry.contains("desktop") || entry.contains("claude-ai") { session.surface = .desktop }
        else if entry.contains("vscode") || entry.contains("ide") { session.surface = .vscode }
        else if entry == "cli" { session.surface = .cli }
        if type == "custom-title", let title = row["customTitle"] as? String { session.title = title }
        guard let at = AgentEventParser.date(row["timestamp"]), at >= session.updatedAt else { return }
        let previous = session.state
        let message = row["message"] as? [String: Any] ?? [:]
        let content = message["content"]
        let blocks = content as? [[String: Any]] ?? []
        if type == "user" && row["isMeta"] as? Bool != true {
            let prompt = content as? String ?? blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if prompt.hasPrefix("[Request interrupted by user") {
                // Esc ends the turn without a Stop hook or an end_turn row.
                if session.state.isActive { session.state = .interrupted; session.finishedAt = at }
                session.toolIsRunning = false; session.waitingCallID = nil
            } else if let command = ClaudeActivityParser.slashCommand(prompt) {
                session.pendingPrompt = command
                session.pendingTurnID = row["uuid"] as? String ?? at.ISO8601Format()
                return
            } else if ClaudeActivityParser.isLocalCommand(prompt) {
                // Built-in command output and !commands are not model turns.
                session.pendingPrompt = nil; session.pendingTurnID = nil
                return
            } else if !prompt.isEmpty && !blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                session.pendingPrompt = nil; session.pendingTurnID = nil
                session.userPrompt = String(prompt.prefix(4000)); session.turnID = row["uuid"] as? String ?? at.ISO8601Format()
                session.startedAt = at; session.finishedAt = nil; session.state = .running; session.waitingCallID = nil
                session.tool = ""; session.activityDetail = ""; session.toolIsRunning = false
            } else if blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                session.toolIsRunning = false
                if session.state == .waiting { session.state = .running; session.waitingCallID = nil }
            }
        } else if type == "assistant" {
            if let turn = session.pendingTurnID {
                session.userPrompt = session.pendingPrompt ?? ""; session.turnID = turn
                session.startedAt = at; session.finishedAt = nil; session.state = .running; session.waitingCallID = nil
                session.tool = ""; session.activityDetail = ""; session.toolIsRunning = false
                session.pendingPrompt = nil; session.pendingTurnID = nil
            }
            for block in blocks where block["type"] as? String == "tool_use" {
                session.tool = block["name"] as? String ?? ""; session.toolCallID = block["id"] as? String ?? ""
                session.activityDetail = AgentEventParser.activityInput(block["input"], tool: session.tool)
                session.toolIsRunning = true; session.state = .running
                if session.tool == "AskUserQuestion" { session.state = .waiting; session.waitingCallID = session.toolCallID; session.attentionRevision = session.toolCallID }
            }
            if message["stop_reason"] as? String == "end_turn" { session.state = .completed; session.finishedAt = at; session.toolIsRunning = false }
        } else if type == "system", row["subtype"] as? String == "turn_duration" {
            session.state = .completed; session.finishedAt = at; session.toolIsRunning = false
        } else { return }
        if previous != session.state { session.attentionRevision = AgentEventParser.revision(at) }
        session.updatedAt = at
    }
    static func isLocalCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["<local-command-stdout>", "<local-command-stderr>", "<local-command-caveat>",
                "<bash-input>", "<bash-stdout>", "<bash-stderr>"].contains { trimmed.hasPrefix($0) }
    }

    /// "/review" from a "<command-name>/review</command-name>…" row, or nil for anything else.
    static func slashCommand(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<command-name>") || trimmed.hasPrefix("<command-message>") else { return nil }
        if let start = trimmed.range(of: "<command-name>"), let end = trimmed.range(of: "</command-name>"),
           start.upperBound <= end.lowerBound {
            let name = trimmed[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
            var command = name.hasPrefix("/") ? name : "/" + name
            if let a = trimmed.range(of: "<command-args>"), let b = trimmed.range(of: "</command-args>"), a.upperBound <= b.lowerBound {
                let args = trimmed[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !args.isEmpty { command += " " + args }
            }
            return String(command.prefix(4000))
        }
        return "/"
    }

    static func applyHook(_ event: [String: Any], to session: inout AgentSession) {
        guard event["session_id"] as? String == session.id, let at = AgentEventParser.date(event["timestamp"]), at >= session.updatedAt else { return }
        let previous = session.state
        switch event["event"] as? String {
        case "UserPromptSubmit": session.state = .running; session.startedAt = at; session.finishedAt = nil; session.turnID = at.ISO8601Format()
        case "PermissionRequest":
            session.state = .waiting; session.attentionRevision = AgentEventParser.revision(at)
        case "PreToolUse", "PostToolUse": session.state = .running; session.waitingCallID = nil
        // Other Stop handlers can continue the response; transcript boundaries certify completion.
        case "Stop": break
        case "SessionEnd": if session.state.isActive { session.state = .interrupted; session.finishedAt = at }
        default: return
        }
        if previous != session.state { session.attentionRevision = AgentEventParser.revision(at) }
        session.updatedAt = at
    }
}
