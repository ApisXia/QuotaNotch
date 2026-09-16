// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SQLite3

struct AgentActivitySnapshot {
    var sessions: [AgentSession] = []
    var hasDatabase = false
    var hasSessionDirectory = false
    var issue: String?
    var truncated = false
}

/// Reads only metadata columns. Never requests prompts, responses, credentials, or tool output.
struct AgentMetadataDatabase {
    let url: URL
    func read() throws -> (sessions: [AgentSession], projects: [AgentProject], truncated: Bool) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw CocoaError(.fileReadNoPermission)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        func rows(_ sql: String) throws -> [[String: String]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
            defer { sqlite3_finalize(statement) }
            var result: [[String: String]] = []
            var code = sqlite3_step(statement)
            while code == SQLITE_ROW {
                var row: [String: String] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    if let text = sqlite3_column_text(statement, index) {
                        row[String(cString: sqlite3_column_name(statement, index))] = String(cString: text)
                    }
                }
                result.append(row); code = sqlite3_step(statement)
            }
            guard code == SQLITE_DONE else { throw CocoaError(.fileReadUnknown) }
            return result
        }
        let columns = Set(try rows("PRAGMA table_info(threads)").compactMap { $0["name"] })
        let desired = ["id", "rollout_path", "cwd", "title", "name", "project_id", "source", "originator", "archived", "updated_at"]
        let selected = desired.filter { columns.contains($0) }
        guard columns.contains("id"), columns.contains("rollout_path") else { throw CocoaError(.fileReadCorruptFile) }
        let order = columns.contains("updated_at") ? " ORDER BY updated_at DESC" : ""
        let recent = columns.contains("updated_at") ? " WHERE updated_at >= \(Int(Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970))" : ""
        let records = try rows("SELECT " + selected.joined(separator: ",") + " FROM threads" + recent + order + " LIMIT 2001")
        var sessions: [AgentSession] = []
        for row in records.prefix(2000) {
            guard let id = row["id"] else { continue }
            var session = AgentSession(id: id)
            session.cwd = row["cwd"] ?? ""; session.rolloutPath = row["rollout_path"] ?? ""
            session.title = row["name"].flatMap { $0.isEmpty ? nil : $0 } ?? row["title"] ?? ""
            session.projectID = row["project_id"]
            session.hasProjectAssignment = columns.contains("project_id")
            session.archived = row["archived"] == "1"
            let source = row["source"] ?? ""
            let originator = row["originator"] ?? ""
            if originator.contains("desktop") || originator.contains("app") { session.surface = .desktop }
            else if source == "vscode" { session.surface = .vscode }
            else if source == "cli" { session.surface = .cli }
            session.excluded = source.contains("subagent")
            sessions.append(session)
        }
        let projectRows = (try? rows("SELECT id, name FROM projects")) ?? []
        let roots = (try? rows("SELECT project_id, path FROM project_roots ORDER BY position")) ?? []
        let projects = projectRows.compactMap { row -> AgentProject? in
            guard let id = row["id"], let name = row["name"] else { return nil }
            return AgentProject(id: id, name: name, roots: roots.filter { $0["project_id"] == id }.compactMap { $0["path"] })
        }
        return (sessions, projects, records.count > 2000)
    }
}

actor AgentActivityRepository {
    let home: URL
    let hookDirectory: URL
    private var cursors: [String: AgentLogCursor] = [:]
    private var cache: [String: AgentSession] = [:]
    private var identities: [String: UInt64] = [:]
    private var metadata: [AgentSession] = []
    private var projects: [AgentProject] = []
    private var global: [String: Any] = [:]
    private var indexTitles: [String: String] = [:]
    private var rootCache: [String: String] = [:]
    private var metadataReadAt = Date.distantPast
    private var hasDatabase = false
    private var truncated = false
    private var metadataIssue: String?

    init(home: URL, hookDirectory: URL) { self.home = home; self.hookDirectory = hookDirectory }

    func scan(now: Date = Date(), force: Bool = false) -> AgentActivitySnapshot {
        if force || now.timeIntervalSince(metadataReadAt) >= 8 {
            refreshMetadata(); metadataReadAt = now
        }
        var result = AgentActivitySnapshot(hasDatabase: hasDatabase,
            hasSessionDirectory: FileManager.default.fileExists(atPath: home.appendingPathComponent("sessions").path),
            issue: metadataIssue, truncated: truncated)
        var readFailure = false
        for record in metadata where !record.archived && !record.excluded {
            guard !record.rolloutPath.isEmpty else { continue }
            let path = record.rolloutPath
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? UInt64 else { continue }
            let inode = attributes[.systemFileNumber] as? UInt64 ?? 0
            var cursor = cursors[path] ?? AgentLogCursor()
            var session = cache[path] ?? record
            if cursor.offset > size || identities[path].map({ $0 != inode }) == true {
                cursor = AgentLogCursor(); session = record
            }
            if cursor.offset < size {
                do {
                    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                    defer { try? handle.close() }
                    if cursor.offset == 0 && size > 2 * 1024 * 1024 {
                        // Read the identity at the head, then recent lifecycle events at the tail.
                        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
                        var header = AgentLogCursor()
                        header.consume(head) { AgentEventParser.apply($0, to: &session) }
                        // Identity survives the gap; an old turn at the head must not veto
                        // the latest completion in the tail of a long conversation.
                        session.state = .unknown; session.turnID = ""; session.updatedAt = .distantPast
                        session.startedAt = nil; session.finishedAt = nil; session.waitingCallID = nil; session.tool = ""
                        session.userPrompt = ""; session.activityDetail = ""; session.toolCallID = ""; session.toolIsRunning = false; session.attentionRevision = ""
                        cursor.offset = size - 2 * 1024 * 1024
                        cursor.skipping = true
                    }
                    try handle.seek(toOffset: cursor.offset)
                    let bytes = try handle.read(upToCount: 2 * 1024 * 1024) ?? Data()
                    cursor.consume(bytes) { AgentEventParser.apply($0, to: &session) }
                    cursors[path] = cursor; identities[path] = inode
                } catch { readFailure = true }
            }
            session.title = record.title.isEmpty ? (indexTitles[session.id] ?? "") : record.title
            session.archived = record.archived
            if session.surface == .unknown { session.surface = record.surface }
            let hookURL = hookDirectory.appendingPathComponent(session.id + ".json")
            if UUID(uuidString: session.id) != nil, let data = try? boundedData(hookURL, limit: 8192),
               let hook = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                AgentEventParser.applyHook(hook, to: &session)
            }
            cache[path] = session
            if session.excluded { continue }
            if session.state == .running && now.timeIntervalSince(session.updatedAt) > 12 * 3600 {
                session.state = .unknown
            }
            // Reading, not a one-day timer, dismisses finished attention within the local history window.
            var assignment = record.projectID
            if !record.hasProjectAssignment, assignment == nil,
               let assignments = global["thread-project-assignments"] as? [String: [String: String]],
               let legacy = assignments[session.id]?["projectId"] {
                let maps = global["app-server-project-id-by-legacy-project-id-by-host"] as? [String: [String: String]] ?? [:]
                assignment = maps.values.compactMap { $0[legacy] }.first ?? legacy
            }
            let hints = global["thread-workspace-root-hints"] as? [String: String] ?? [:]
            let base = hints[session.id] ?? session.cwd
            if rootCache[base] == nil { rootCache[base] = AgentProjectResolver.repositoryRoot(for: base) }
            let projectless = record.hasProjectAssignment ? record.projectID == nil
                : (global["projectless-thread-ids"] as? [String] ?? []).contains(session.id)
            session = AgentProjectResolver.resolve(session, projects: projects, assignedID: assignment,
                rootHint: rootCache[base], projectless: projectless)
            result.sessions.append(session)
        }
        if readFailure { result.issue = "Some task records could not be read. Retrying automatically." }
        // Some clients move/duplicate a rollout during resume. Identity, not path, owns a task.
        var unique: [String: AgentSession] = [:]
        for session in result.sessions {
            if let previous = unique[session.id], previous.updatedAt > session.updatedAt { continue }
            unique[session.id] = session
        }
        result.sessions = unique.values.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            return $0.updatedAt > $1.updatedAt
        }
        return result
    }

    private func boundedData(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    private func refreshMetadata() {
        let fm = FileManager.default
        metadataIssue = nil
        if let data = try? boundedData(home.appendingPathComponent(".codex-global-state.json"), limit: 8 * 1024 * 1024),
           let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { global = value }
        if let data = try? boundedData(home.appendingPathComponent("session_index.jsonl"), limit: 16 * 1024 * 1024) {
            for line in data.split(separator: 10) {
                if let row = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                   let id = row["id"] as? String, let name = row["thread_name"] as? String { indexTitles[id] = name }
            }
        }
        let databases = ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        hasDatabase = false
        for database in databases {
            if let result = try? AgentMetadataDatabase(url: database).read() {
                metadata = result.sessions; projects = result.projects; truncated = result.truncated
                hasDatabase = true; break
            }
        }
        if !hasDatabase {
            if !databases.isEmpty { metadataIssue = "Codex metadata is unavailable. Using local task records." }
            let sessionsURL = home.appendingPathComponent("sessions")
            if let files = fm.enumerator(at: sessionsURL, includingPropertiesForKeys: [.contentModificationDateKey],
                                         options: [.skipsHiddenFiles]) {
                var recent: [(URL, Date)] = []
                for case let url as URL in files where url.pathExtension == "jsonl" {
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    if date > Date().addingTimeInterval(-7 * 86400) { recent.append((url, date)) }
                }
                recent.sort { $0.1 > $1.1 }; truncated = recent.count > 2000
                metadata = recent.prefix(2000).map { AgentSession(id: $0.0.lastPathComponent, rolloutPath: $0.0.path) }
            } else { metadata = [] }
            projects = []
        }
        let legacy = global["local-projects"] as? [String: [String: Any]] ?? [:]
        let mappings = global["app-server-project-id-by-legacy-project-id-by-host"] as? [String: [String: String]] ?? [:]
        for (id, item) in legacy {
            let mapped = mappings.values.compactMap { $0[id] }.first ?? id
            let roots = item["rootPaths"] as? [String] ?? []
            if let index = projects.firstIndex(where: { $0.id == mapped }) {
                if projects[index].roots.isEmpty { projects[index].roots = roots }
            }
            else { projects.append(AgentProject(id: mapped, name: item["name"] as? String ?? "", roots: roots)) }
        }
        let labels = global["electron-workspace-root-labels"] as? [String: String] ?? [:]
        for root in global["electron-saved-workspace-roots"] as? [String] ?? [] {
            if !projects.contains(where: { $0.roots.contains(root) }) {
                projects.append(AgentProject(id: "folder:" + root, name: labels[root] ?? URL(fileURLWithPath: root).lastPathComponent, roots: [root]))
            }
        }
        let paths = Set(metadata.map(\.rolloutPath))
        cache = cache.filter { paths.contains($0.key) }; cursors = cursors.filter { paths.contains($0.key) }
        identities = identities.filter { paths.contains($0.key) }
    }
}
