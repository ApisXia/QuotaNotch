// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SQLite3
@testable import QuotaNotchCore

final class AgentActivityTests: XCTestCase {
    private let id = "11111111-1111-4111-8111-111111111111"
    private let start = Date(timeIntervalSince1970: 1800000000)
    private func event(_ type: String, _ payload: [String: Any], at: Date? = nil) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": type, "timestamp": (at ?? start).ISO8601Format(), "payload": payload])
    }
    private func started() -> AgentSession {
        var s = AgentSession(id: id)
        AgentEventParser.apply(event("event_msg", ["type": "task_started", "turn_id": "one"]), to: &s)
        return s
    }
    func testDesktopSourceTakesPrecedenceOverVSCodeCompatibilitySource() {
        var s = AgentSession(id: id)
        AgentEventParser.apply(event("session_meta", ["id": id, "source": "vscode", "originator": "codex_work_desktop", "cwd": "/work/one"]), to: &s)
        XCTAssertEqual(s.surface, .desktop); XCTAssertEqual(s.cwd, "/work/one")
    }
    func testDesktopNullParentIsNotAChildTask() {
        var s = AgentSession(id: id)
        AgentEventParser.apply(event("session_meta", ["id": id, "originator": "codex_work_desktop",
            "source": "vscode", "parent_thread_id": NSNull()]), to: &s)
        XCTAssertFalse(s.excluded)
        XCTAssertEqual(s.surface, .desktop)
    }
    func testStructuredNonSubagentSourceIsNotExcluded() {
        var s = AgentSession(id: id)
        AgentEventParser.apply(event("session_meta", ["id": id, "originator": "codex_work_desktop",
            "source": ["other": "desktop"]]), to: &s)
        XCTAssertFalse(s.excluded)
    }
    func testVSCodeSourceAndHandoff() {
        var s = AgentSession(id: id, surface: .desktop)
        AgentEventParser.apply(event("session_meta", ["id": id, "source": "vscode", "originator": "codex_vscode"]), to: &s)
        XCTAssertEqual(s.surface, .vscode)
    }
    func testInternalAgentsDoNotBecomeSeparateUserTasks() {
        var s = AgentSession(id: id)
        AgentEventParser.apply(event("session_meta", ["id": id, "source": ["subagent": ["other": "guardian"]]]), to: &s)
        XCTAssertTrue(s.excluded)
        AgentEventParser.apply(event("session_meta", ["id": id, "source": "vscode", "thread_source": "thread_title"]), to: &s)
        XCTAssertTrue(s.excluded)
    }
    func testStartCompleteAndNewTurn() {
        var s = started(); XCTAssertEqual(s.state, .running)
        AgentEventParser.apply(event("event_msg", ["type": "task_complete", "turn_id": "one"], at: start.addingTimeInterval(2)), to: &s)
        XCTAssertEqual(s.state, .completed); XCTAssertNotNil(s.finishedAt)
        AgentEventParser.apply(event("event_msg", ["type": "task_started", "turn_id": "two"], at: start.addingTimeInterval(3)), to: &s)
        XCTAssertEqual(s.state, .running); XCTAssertNil(s.finishedAt); XCTAssertEqual(s.turnID, "two")
    }
    func testOldTurnCompletionCannotStopNewTurn() {
        var s = started()
        AgentEventParser.apply(event("event_msg", ["type": "task_complete", "turn_id": "older"], at: start.addingTimeInterval(1)), to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testOutOfOrderEventIgnored() {
        var s = started()
        AgentEventParser.apply(event("event_msg", ["type": "turn_aborted", "turn_id": "one"], at: start.addingTimeInterval(-2)), to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testInterruptedIsNotSuccessful() {
        var s = started(); AgentEventParser.apply(event("event_msg", ["type": "turn_aborted", "turn_id": "one"]), to: &s)
        XCTAssertEqual(s.state, .interrupted)
    }
    func testAssistantFinalTextDoesNotCertifyCompletion() {
        var s = started()
        AgentEventParser.apply(event("response_item", ["type": "message", "phase": "final_answer", "role": "assistant"]), to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testWaitingQuestionAndMatchingAnswer() {
        var s = started()
        AgentEventParser.apply(event("response_item", ["type": "function_call", "name": "request_user_input", "call_id": "q"]), to: &s)
        XCTAssertEqual(s.state, .waiting)
        AgentEventParser.apply(event("response_item", ["type": "function_call_output", "call_id": "different"]), to: &s)
        XCTAssertEqual(s.state, .waiting)
        AgentEventParser.apply(event("response_item", ["type": "function_call_output", "call_id": "q"]), to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testAsyncQuestionDoesNotClaimAgentStopped() {
        var s = started()
        AgentEventParser.apply(event("response_item", ["type": "function_call", "name": "request_user_input_async"]), to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testRetryableErrorDoesNotFailTask() {
        var s = started()
        AgentEventParser.apply(event("event_msg", ["type": "error", "will_retry": true]), to: &s)
        XCTAssertEqual(s.state, .running)
        AgentEventParser.apply(event("event_msg", ["type": "error", "will_retry": false]), to: &s)
        XCTAssertEqual(s.state, .failed)
    }
    func testPermissionHookAndResumedTool() {
        var s = started()
        AgentEventParser.applyHook(["session_id": id, "turn_id": "one", "event": "PermissionRequest", "timestamp": start.ISO8601Format()], to: &s)
        XCTAssertEqual(s.state, .waiting)
        AgentEventParser.applyHook(["session_id": id, "turn_id": "one", "event": "PreToolUse", "timestamp": start.ISO8601Format()], to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testStopHookDoesNotAnnouncePrematureCompletion() {
        var s = started()
        AgentEventParser.applyHook(["session_id": id, "event": "Stop", "timestamp": start.ISO8601Format()], to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testWrongSessionAndStaleHooksIgnored() {
        var s = started()
        for entry in [["session_id": "wrong", "event": "PermissionRequest", "timestamp": start.ISO8601Format()],
                      ["session_id": id, "turn_id": "wrong", "event": "PermissionRequest", "timestamp": start.ISO8601Format()],
                      ["session_id": id, "event": "PermissionRequest", "timestamp": start.addingTimeInterval(-10).ISO8601Format()]] {
            AgentEventParser.applyHook(entry, to: &s)
        }
        XCTAssertEqual(s.state, .running)
    }
    func testSilenceIsNotFailure() {
        let s = started(); XCTAssertTrue(s.isQuiet(at: start.addingTimeInterval(500)))
        XCTAssertEqual(s.state, .running)
    }
    func testProjectRenameAndExplicitAssignmentBeatsDirectory() {
        let s = AgentSession(id: id, cwd: "/work/one")
        let projects = [AgentProject(id: "a", name: "One", roots: ["/work/one"]), AgentProject(id: "b", name: "Renamed", roots: ["/work/two"])]
        let result = AgentProjectResolver.resolve(s, projects: projects, assignedID: "b", rootHint: nil)
        XCTAssertEqual(result.projectName, "Renamed"); XCTAssertEqual(result.groupID, "project:b")
    }
    func testLongestRootBoundaryAndProjectless() {
        let projects = [AgentProject(id: "a", name: "Parent", roots: ["/work"]), AgentProject(id: "b", name: "Child", roots: ["/work/app"])]
        let s = AgentSession(id: id, cwd: "/work/app/src")
        XCTAssertEqual(AgentProjectResolver.resolve(s, projects: projects, assignedID: nil, rootHint: nil).projectName, "Child")
        XCTAssertFalse(AgentProjectResolver.contains("/work/app", "/work/apple"))
        let free = AgentProjectResolver.resolve(s, projects: projects, assignedID: nil, rootHint: "/work/app", projectless: true)
        XCTAssertNil(free.projectID); XCTAssertEqual(free.projectName, "app")
    }
    func testSameFolderNameDoesNotMergeDifferentRoots() {
        let a = AgentProjectResolver.resolve(AgentSession(id: "a", cwd: "/one/app"), projects: [], assignedID: nil, rootHint: nil)
        let b = AgentProjectResolver.resolve(AgentSession(id: "b", cwd: "/two/app"), projects: [], assignedID: nil, rootHint: nil)
        XCTAssertEqual(a.projectName, b.projectName); XCTAssertNotEqual(a.groupID, b.groupID)
    }
    func testChunkedUnicodeLinesAndPartialWrite() {
        let line = event("event_msg", ["type": "task_started", "turn_id": "中文"])
        var cursor = AgentLogCursor(); var results: [Data] = []
        let bytes = line + Data([10]) + line
        for byte in bytes { cursor.consume(Data([byte])) { results.append($0) } }
        XCTAssertEqual(results, [line]); XCTAssertEqual(cursor.pending, line)
        cursor.consume(Data([10])) { results.append($0) }; XCTAssertEqual(results.count, 2)
    }
    func testOversizedLineDoesNotHideNextEvent() {
        var cursor = AgentLogCursor(); var lines: [Data] = []
        cursor.consume(Data(repeating: 120, count: cursor.lineLimit + 1)) { lines.append($0) }
        cursor.consume(Data("\n{}\n".utf8)) { lines.append($0) }
        XCTAssertEqual(lines, [Data("{}".utf8)]); XCTAssertTrue(cursor.pending.isEmpty)
    }
    func testMalformedAndUnknownRecordsPreserveState() {
        var s = started(); AgentEventParser.apply(Data("broken".utf8), to: &s)
        AgentEventParser.apply(event("new_record", ["type": "future_event"]), to: &s)
        XCTAssertEqual(s.state, .running)
    }
    func testHookInstallUpdateRemovePreservesOtherHandlers() throws {
        let original = Data(#"{"description":"keep","hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"existing"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"start"}]}]}}"#.utf8)
        let installed = try AgentHookConfiguration.updating(original, helper: "/a path/it's/helper", eventDirectory: "/events")
        let twice = try AgentHookConfiguration.updating(installed, helper: "/a path/it's/helper", eventDirectory: "/events")
        XCTAssertEqual(installed, twice)
        let removed = try AgentHookConfiguration.updating(twice, helper: nil, eventDirectory: "/events")
        let before = try JSONSerialization.jsonObject(with: original) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: removed) as! NSDictionary
        XCTAssertEqual(before, after)
        XCTAssertThrowsError(try AgentHookConfiguration.updating(Data("broken".utf8), helper: "/helper", eventDirectory: "/events"))
    }
}

final class AgentRepositoryTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func append(_ data: String, file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(data.utf8))
    }
    private func line(_ type: String, _ payload: [String: Any], at: Date = Date()) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["timestamp": at.ISO8601Format(), "type": type, "payload": payload])
        return String(data: data, encoding: .utf8)! + "\n"
    }
    func testAppendTruncateAndRepeatedReads() async throws {
        let file = root.appendingPathComponent("sessions/one.jsonl")
        let id = UUID().uuidString
        try append(line("session_meta", ["id": id, "cwd": "/projects/demo", "originator": "codex_vscode", "source": "vscode"]), file: file)
        try append(line("event_msg", ["type": "task_started", "turn_id": "one"]), file: file)
        let repository = AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events"))
        let first = await repository.scan(force: true)
        XCTAssertEqual(first.sessions.count, 1); XCTAssertEqual(first.sessions.first?.state, .running)
        let again = await repository.scan(); XCTAssertEqual(again.sessions, first.sessions)
        try append(line("event_msg", ["type": "task_complete", "turn_id": "one"]), file: file)
        let finished = await repository.scan(); XCTAssertEqual(finished.sessions.first?.state, .completed)
        try Data((try line("session_meta", ["id": id, "cwd": "/projects/changed", "source": "vscode"]) + line("event_msg", ["type": "task_started", "turn_id": "new"])).utf8).write(to: file, options: .atomic)
        let replaced = await repository.scan(); XCTAssertEqual(replaced.sessions.first?.turnID, "new")
        XCTAssertEqual(replaced.sessions.first?.projectName, "changed")
        try append(line("response_item", ["type": "function_call", "name": "request_user_input", "call_id": "pending"]), file: file)
        let overnight = await repository.scan(now: Date().addingTimeInterval(14 * 3600))
        XCTAssertEqual(overnight.sessions.first?.state, .waiting, "Reading or elapsed time must not resolve a pending request")
    }
    func testDatabaseProjectRenameArchiveAndReadOnlyAccess() async throws {
        let file = root.appendingPathComponent("sessions/one.jsonl"); let id = UUID().uuidString
        try append(line("session_meta", ["id": id, "cwd": "/work/root/sub", "source": "vscode"]), file: file)
        try append(line("event_msg", ["type": "task_started", "turn_id": "one"]), file: file)
        let database = root.appendingPathComponent("state_5.sqlite")
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        let sql = "CREATE TABLE threads(id TEXT, rollout_path TEXT, cwd TEXT, title TEXT, name TEXT, project_id TEXT, source TEXT, archived INTEGER, updated_at INTEGER); CREATE TABLE projects(id TEXT,name TEXT); CREATE TABLE project_roots(project_id TEXT,path TEXT,position INTEGER); INSERT INTO projects VALUES('p','Custom project'); INSERT INTO project_roots VALUES('p','/work/root',0); INSERT INTO threads VALUES('\(id)','\(file.path)','/work/root/sub','Old title','New title','p','vscode',0,\(Int(Date().timeIntervalSince1970)));"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let repository = AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events"))
        let first = await repository.scan(force: true)
        XCTAssertTrue(first.hasDatabase); XCTAssertEqual(first.sessions.first?.projectName, "Custom project")
        XCTAssertEqual(first.sessions.first?.projectRoot, "/work/root"); XCTAssertEqual(first.sessions.first?.title, "New title")
        XCTAssertEqual(sqlite3_exec(db, "UPDATE projects SET name='Renamed'", nil, nil, nil), SQLITE_OK)
        let renamed = await repository.scan(force: true); XCTAssertEqual(renamed.sessions.first?.projectName, "Renamed")
        try JSONSerialization.data(withJSONObject: ["thread-project-assignments": [id: ["projectId": "p"]]])
            .write(to: root.appendingPathComponent(".codex-global-state.json"))
        XCTAssertEqual(sqlite3_exec(db, "UPDATE threads SET project_id=NULL", nil, nil, nil), SQLITE_OK)
        let unassigned = await repository.scan(force: true)
        XCTAssertNil(unassigned.sessions.first?.projectID)
        XCTAssertNotEqual(unassigned.sessions.first?.projectName, "Renamed")
        XCTAssertEqual(sqlite3_exec(db, "UPDATE threads SET archived=1", nil, nil, nil), SQLITE_OK)
        let archived = await repository.scan(force: true); XCTAssertTrue(archived.sessions.isEmpty)
    }
    private func createDiscoveryDatabase() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK, let db else {
            throw CocoaError(.fileWriteUnknown)
        }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE threads(id TEXT, rollout_path TEXT, cwd TEXT, title TEXT, source TEXT, archived INTEGER, updated_at INTEGER)", nil, nil, nil), SQLITE_OK)
        return db
    }
    private func desktopLog(_ id: String, name: String? = nil) throws -> URL {
        let file = root.appendingPathComponent("sessions/" + (name ?? id + ".jsonl"))
        try append(line("session_meta", ["id": id, "cwd": "/projects/desktop", "originator": "codex_work_desktop", "source": "vscode"]), file: file)
        try append(line("event_msg", ["type": "task_started", "turn_id": "live"]), file: file)
        return file
    }
    func testReadableEmptyDatabaseStillDiscoversDesktopLog() async throws {
        let db = try createDiscoveryDatabase(); defer { sqlite3_close(db) }
        let id = UUID().uuidString
        _ = try desktopLog(id)
        let snapshot = await AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events")).scan(force: true)
        XCTAssertTrue(snapshot.hasDatabase)
        XCTAssertEqual(snapshot.sessions.map(\.id), [id])
        XCTAssertEqual(snapshot.sessions.first?.state, .running)
    }
    func testStaleIndexKeepsFreshLogAndAuthoritativeTitle() async throws {
        let db = try createDiscoveryDatabase(); defer { sqlite3_close(db) }
        let id = UUID().uuidString
        let file = try desktopLog(id)
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES('\(id)','\(file.path)','/projects/desktop','My renamed task','vscode',0,1)", nil, nil, nil), SQLITE_OK)
        let snapshot = await AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events")).scan(force: true)
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.title, "My renamed task")
        XCTAssertEqual(snapshot.sessions.first?.state, .running)
    }
    func testStaleArchivedIndexMustNotBeResurrectedByFreshLog() async throws {
        let db = try createDiscoveryDatabase(); defer { sqlite3_close(db) }
        let id = UUID().uuidString
        let file = try desktopLog(id)
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES('\(id)','\(file.path)','/projects/desktop','Archived task','vscode',1,1)", nil, nil, nil), SQLITE_OK)
        let snapshot = await AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events")).scan(force: true)
        XCTAssertTrue(snapshot.sessions.isEmpty)
    }
    func testMovedDesktopRolloutKeepsTitleAndArchiveState() async throws {
        let db = try createDiscoveryDatabase(); defer { sqlite3_close(db) }
        let id = UUID().uuidString
        _ = try desktopLog(id, name: "rollout-moved-" + id + ".jsonl")
        let oldPath = root.appendingPathComponent("missing.jsonl").path
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES('\(id)','\(oldPath)','/projects/desktop','Moved task','vscode',0,1)", nil, nil, nil), SQLITE_OK)
        let repository = AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events"))
        let active = await repository.scan(force: true)
        XCTAssertEqual(active.sessions.count, 1)
        XCTAssertEqual(active.sessions.first?.title, "Moved task")
        XCTAssertEqual(active.sessions.first?.state, .running)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE threads SET archived=1", nil, nil, nil), SQLITE_OK)
        let archived = await repository.scan(force: true)
        XCTAssertTrue(archived.sessions.isEmpty)
    }
    func testSupplementalLogPathWithQuoteAndLateIndexDoesNotDuplicate() async throws {
        let db = try createDiscoveryDatabase(); defer { sqlite3_close(db) }
        let id = UUID().uuidString
        let file = try desktopLog(id, name: "user's-log.jsonl")
        let repository = AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events"))
        let first = await repository.scan(force: true)
        XCTAssertEqual(first.sessions.count, 1)
        let escaped = file.path.replacingOccurrences(of: "'", with: "''")
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES('\(id)','\(escaped)','/projects/desktop','Renamed later','vscode',0,1)", nil, nil, nil), SQLITE_OK)
        let indexed = await repository.scan(force: true)
        XCTAssertEqual(indexed.sessions.count, 1)
        XCTAssertEqual(indexed.sessions.first?.title, "Renamed later")
    }
    func testWorktreeResolvesToRepository() throws {
        let main = root.appendingPathComponent("main", isDirectory: true)
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let git = main.appendingPathComponent(".git/worktrees/feature", isDirectory: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("gitdir: \(git.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        try Data("../..\n".utf8).write(to: git.appendingPathComponent("commondir"))
        XCTAssertEqual(AgentProjectResolver.repositoryRoot(for: worktree.appendingPathComponent("src").path), main.path)
    }
    func testManyParallelProjectsAndDuplicateSession() async throws {
        for i in 0..<60 {
            let id = UUID().uuidString
            let content = try line("session_meta", ["id": id, "cwd": "/projects/\(i % 12)", "source": "vscode"]) + line("event_msg", ["type": "task_started", "turn_id": "one"])
            try append(content, file: root.appendingPathComponent("sessions/\(i).jsonl"))
            if i == 0 { try append(content, file: root.appendingPathComponent("sessions/duplicate.jsonl")) }
        }
        let repository = AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events"))
        let snapshot = await repository.scan(force: true)
        XCTAssertEqual(snapshot.sessions.count, 60); XCTAssertEqual(Set(snapshot.sessions.map(\.groupID)).count, 12)
    }
    func testLargeConversationTailDoesNotReuseOldTurn() async throws {
        let file = root.appendingPathComponent("sessions/long.jsonl"); let id = UUID().uuidString
        try append(line("session_meta", ["id": id, "cwd": "/projects/long", "source": "vscode"]), file: file)
        try append(line("event_msg", ["type": "task_started", "turn_id": "old"]), file: file)
        try append(line("event_msg", ["type": "user_message", "message": "Old request outside the tail"]), file: file)
        try append(String(repeating: "x", count: 3 * 1024 * 1024) + "\n", file: file)
        try append(line("event_msg", ["type": "task_complete", "turn_id": "new"]), file: file)
        let repository = AgentActivityRepository(home: root, hookDirectory: root.appendingPathComponent("events"))
        let snapshot = await repository.scan(force: true)
        XCTAssertEqual(snapshot.sessions.first?.state, .completed)
        XCTAssertEqual(snapshot.sessions.first?.turnID, "new")
        XCTAssertEqual(snapshot.sessions.first?.userPrompt, "")
    }
}
