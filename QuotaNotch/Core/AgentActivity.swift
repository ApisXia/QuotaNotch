// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AgentRunState: String, Codable, CaseIterable {
    case running, waiting, completed, interrupted, failed, unknown
    var priority: Int {
        switch self { case .waiting: return 0; case .failed: return 1; case .running: return 2
        case .completed: return 3; case .interrupted: return 4; case .unknown: return 5 }
    }
    var isActive: Bool { self == .running || self == .waiting }
}

enum AgentProvider: String, Codable { case codex, claude }

enum AgentSurface: String, Codable { case desktop, vscode, cli, unknown }

struct AgentSession: Identifiable, Equatable, Codable {
    var id: String
    var provider: AgentProvider = .codex
    var title = ""
    var cwd = ""
    var projectID: String?
    var hasProjectAssignment = false
    var projectName = ""
    var projectRoot = ""
    var surface: AgentSurface = .unknown
    var state: AgentRunState = .unknown
    var turnID = ""
    var updatedAt = Date.distantPast
    var startedAt: Date?
    var finishedAt: Date?
    var tool = ""
    var userPrompt = ""
    var activityDetail = ""
    var toolCallID = ""
    var toolIsRunning = false
    var attentionRevision = ""
    var identity: String { provider.rawValue + ":" + id }
    var waitingCallID: String?
    var excluded = false
    var archived = false
    var rolloutPath = ""
    var groupID: String { projectID.map { "project:" + $0 } ?? "root:" + projectRoot }
    var displayTitle: String { title.isEmpty ? (provider == .codex ? "Codex · " : "Claude Code · ") + String(id.prefix(8)) : title }
    var eventID: String { identity + ":" + turnID + ":" + state.rawValue + ":" + attentionRevision }
    func isQuiet(at now: Date) -> Bool { state == .running && now.timeIntervalSince(updatedAt) > 120 }
}

struct AgentProject: Equatable {
    var id: String
    var name: String
    var roots: [String] = []
}

enum AgentProjectResolver {
    static func contains(_ root: String, _ path: String) -> Bool {
        guard !root.isEmpty, !path.isEmpty else { return false }
        let root = URL(fileURLWithPath: root).standardized.path
        let path = URL(fileURLWithPath: path).standardized.path
        return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    static func resolve(_ session: AgentSession, projects: [AgentProject], assignedID: String?,
                        rootHint: String?, projectless: Bool = false) -> AgentSession {
        var result = session
        let root = rootHint.flatMap { $0.isEmpty ? nil : $0 } ?? session.cwd
        let explicit = assignedID.flatMap { id in projects.first { $0.id == id } }
        let matching = projects.flatMap { project in project.roots.map { (project, $0) } }
            .filter { contains($0.1, root) }.sorted { $0.1.count > $1.1.count }.first
        let project = explicit ?? (projectless ? nil : matching?.0)
        result.projectID = project?.id
        result.projectRoot = project?.roots.filter { contains($0, root) }.max(by: { $0.count < $1.count }) ?? root
        result.projectName = project?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if result.projectName.isEmpty {
            result.projectName = URL(fileURLWithPath: result.projectRoot).lastPathComponent
        }
        if result.projectName.isEmpty { result.projectName = "Codex" }
        return result
    }

    // Resolve a repository or linked worktree without launching git or executing repository hooks.
    static func repositoryRoot(for path: String, fileManager: FileManager = .default) -> String {
        guard path.hasPrefix("/") else { return path }
        var directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        for _ in 0..<40 {
            let git = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue, let data = try? Data(contentsOf: git), data.count < 8192,
                   let text = String(data: data, encoding: .utf8), text.hasPrefix("gitdir:") {
                    let value = text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                    let gitDirectory = URL(fileURLWithPath: value, isDirectory: true, relativeTo: directory).standardizedFileURL
                    let common = gitDirectory.appendingPathComponent("commondir")
                    if let text = try? String(contentsOf: common, encoding: .utf8), text.count < 8192 {
                        let commonDir = URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                            relativeTo: gitDirectory).standardizedFileURL
                        if commonDir.lastPathComponent == ".git" { return commonDir.deletingLastPathComponent().path }
                    }
                }
                return directory.path
            }
            if directory.path == "/" { break }
            directory.deleteLastPathComponent()
        }
        return path
    }
}

enum AgentEventParser {
    static func revision(_ at: Date) -> String { String(format: "%.6f", at.timeIntervalSince1970) }
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func apply(_ data: Data, to session: inout AgentSession) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let kind = object["type"] as? String, let payload = object["payload"] as? [String: Any] else { return }
        let at = date(object["timestamp"]) ?? session.updatedAt
        if kind == "session_meta" {
            guard let id = (payload["id"] ?? payload["session_id"]) as? String else { return }
            session.id = id
            if let cwd = payload["cwd"] as? String { session.cwd = cwd }
            let source = payload["source"] as? String ?? ""
            let originator = payload["originator"] as? String ?? ""
            let internalSource = payload["thread_source"] as? String ?? ""
            let parent = payload["parent_thread_id"] as? String ?? ""
            let structuredSource = payload["source"] as? [String: Any]
            session.excluded = !parent.isEmpty || structuredSource?["subagent"] != nil
                || ["thread_title", "thread_description", "memory_consolidation", "review"].contains(internalSource)
            if originator.contains("desktop") || originator.contains("app") { session.surface = .desktop }
            else if source == "vscode" || originator.contains("vscode") { session.surface = .vscode }
            else if source == "cli" || originator.contains("cli") { session.surface = .cli }
            return
        }
        if kind == "turn_context" {
            if let cwd = payload["cwd"] as? String { session.cwd = cwd }
            if session.turnID.isEmpty { session.turnID = payload["turn_id"] as? String ?? "" }
            return
        }
        guard at >= session.updatedAt else { return }
        let previousState = session.state
        let event = payload["type"] as? String ?? ""
        if kind == "event_msg" {
            switch event {
            case "task_started":
                session.turnID = payload["turn_id"] as? String ?? at.ISO8601Format()
                session.state = .running; session.startedAt = at; session.finishedAt = nil
                session.tool = ""; session.waitingCallID = nil; session.activityDetail = ""; session.toolIsRunning = false
            case "task_complete", "turn_aborted":
                if let turn = payload["turn_id"] as? String, !session.turnID.isEmpty, turn != session.turnID { return }
                if session.turnID.isEmpty { session.turnID = payload["turn_id"] as? String ?? "" }
                session.state = event == "task_complete" ? .completed : .interrupted
                session.finishedAt = at; session.waitingCallID = nil; session.tool = ""; session.toolIsRunning = false
            case "error":
                // Retryable API errors do not mean the task failed.
                if payload["will_retry"] as? Bool == false { session.state = .failed; session.finishedAt = at }
            case "user_message":
                session.userPrompt = String((payload["message"] as? String ?? "").prefix(4000))
            case "exec_command_begin":
                session.tool = "exec_command"; session.toolIsRunning = true
                session.activityDetail = String((payload["command"] as? [String] ?? []).joined(separator: " ").prefix(240))
            case "exec_command_end": session.toolIsRunning = false
            case "agent_message", "agent_reasoning", "item_completed":
                break
            default: return
            }
        } else if kind == "response_item" {
            if session.state == .unknown && ["function_call", "custom_tool_call", "reasoning"].contains(event) {
                session.state = .running
            }
            if event == "function_call" || event == "custom_tool_call" {
                let tool = payload["name"] as? String ?? ""
                session.tool = String(tool.prefix(100)); session.toolIsRunning = true
                session.toolCallID = payload["call_id"] as? String ?? ""
                session.activityDetail = activityInput(payload["arguments"] ?? payload["input"], tool: tool)
                if tool == "request_user_input" || tool.hasSuffix("__request_user_input") {
                    session.state = .waiting
                    session.waitingCallID = payload["call_id"] as? String
                    session.attentionRevision = session.waitingCallID ?? revision(at)
                }
            } else if event == "function_call_output" || event == "custom_tool_call_output" {
                if payload["call_id"] as? String == session.toolCallID { session.toolIsRunning = false }
                if let pending = session.waitingCallID, payload["call_id"] as? String == pending {
                    session.waitingCallID = nil; session.state = .running
                }
            } else if event == "message", payload["role"] as? String == "user" {
                let content = payload["content"] as? [[String: Any]] ?? []
                session.userPrompt = String(content.compactMap { $0["text"] as? String }.joined(separator: "\n").prefix(4000))
            } else if event != "reasoning" && event != "message" { return }
        } else { return }
        if session.state != previousState { session.attentionRevision = revision(at) }
        session.updatedAt = at
    }

    static func activityInput(_ value: Any?, tool: String) -> String {
        let object: [String: Any]?
        if let text = value as? String, let data = text.data(using: .utf8) {
            object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if tool.hasSuffix("apply_patch") {
                return text.components(separatedBy: "\n").filter { $0.hasPrefix("*** Update File:") || $0.hasPrefix("*** Add File:") || $0.hasPrefix("*** Delete File:") }.map { String($0.dropFirst(4)) }.prefix(3).joined(separator: " · ")
            }
        } else { object = value as? [String: Any] }
        let text = object?["file_path"] as? String ?? object?["path"] as? String ?? object?["cmd"] as? String ?? object?["command"] as? String ?? object?["description"] as? String ?? ""
        return String(text.prefix(240))
    }

    static func applyHook(_ object: [String: Any], to session: inout AgentSession) {
        guard object["session_id"] as? String == session.id,
              let at = date(object["timestamp"]), at >= session.updatedAt,
              let event = object["event"] as? String else { return }
        let turn = object["turn_id"] as? String ?? ""
        if !turn.isEmpty, !session.turnID.isEmpty, turn != session.turnID,
           event != "UserPromptSubmit" { return }
        let previousState = session.state
        switch event {
        case "UserPromptSubmit":
            session.turnID = turn.isEmpty ? at.ISO8601Format() : turn
            session.state = .running; session.startedAt = at; session.finishedAt = nil
        case "PermissionRequest":
            session.state = .waiting
            session.attentionRevision = object["request_id"] as? String ?? revision(at)
        case "PreToolUse", "PostToolUse":
            if session.state == .waiting { session.state = .running; session.waitingCallID = nil }
        case "Interrupt": session.state = .interrupted; session.finishedAt = at
        // Stop is before the final turn boundary, and other hooks can continue the turn.
        // The rollout's task_complete is the authoritative completion signal.
        case "Stop": break
        default: return
        }
        if session.state != previousState { session.attentionRevision = revision(at) }
        session.updatedAt = at
    }
}

/// Incremental JSONL reader: bounded memory, handles partial writes and oversized records.
struct AgentLogCursor {
    var offset: UInt64 = 0
    var pending = Data()
    var skipping = false
    let lineLimit = 4 * 1024 * 1024

    mutating func consume(_ bytes: Data, apply: (Data) -> Void) {
        for part in bytes.split(separator: 10, omittingEmptySubsequences: false).enumerated() {
            if part.offset > 0 {
                if !skipping, !pending.isEmpty { apply(pending) }
                pending.removeAll(keepingCapacity: true); skipping = false
            }
            if !skipping {
                if pending.count + part.element.count <= lineLimit { pending.append(contentsOf: part.element) }
                else { pending.removeAll(keepingCapacity: true); skipping = true }
            }
        }
        offset += UInt64(bytes.count)
    }
}
