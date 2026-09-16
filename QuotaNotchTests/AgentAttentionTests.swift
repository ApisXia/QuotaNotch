// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import QuotaNotchCore

final class AgentAttentionTests: XCTestCase {
    func testEveryStateReadAndUnread() {
        for state in AgentRunState.allCases {
            let session = AgentSession(id: "one", state: state)
            let unread = AgentAttentionSummary.make([session], acknowledged: [:])
            let read = AgentAttentionSummary.make([session], acknowledged: [session.identity: session.eventID])
            XCTAssertEqual(unread.isVisible, state.isActive || state.isUnreadEvent, "\(state)")
            XCTAssertEqual(read.isVisible, state.isActive, "\(state)")
            XCTAssertEqual(unread.unread, state.isUnreadEvent ? 1 : 0)
        }
    }
    func testMixedIncludesRunningAndCountsEachTaskOnce() {
        let running = AgentSession(id: "one", state: .running)
        let waiting = AgentSession(id: "two", state: .waiting)
        let done = AgentSession(id: "three", state: .completed)
        let summary = AgentAttentionSummary.make([running, waiting, done, waiting], acknowledged: [:])
        XCTAssertEqual(summary.count, 3); XCTAssertEqual(summary.kind, .mixed)
        XCTAssertEqual(summary.running, 1); XCTAssertEqual(summary.waiting, 1); XCTAssertEqual(summary.unread, 2)
        XCTAssertTrue(summary.needsAction)
    }
    func testProviderIdentityDoesNotCollide() {
        let codex = AgentSession(id: "one", state: .running)
        var claude = codex; claude.provider = .claude
        XCTAssertEqual(AgentAttentionSummary.make([codex, claude], acknowledged: [:]).count, 2)
    }
    func testRepeatedApprovalInSameSecondBecomesUnreadAgain() {
        var session = AgentSession(id: "one", state: .running)
        AgentEventParser.applyHook(["session_id": "one", "event": "PermissionRequest", "timestamp": "2026-09-16T12:00:00.100Z"], to: &session)
        let read = [session.identity: session.eventID]
        AgentEventParser.applyHook(["session_id": "one", "event": "PermissionRequest", "timestamp": "2026-09-16T12:00:00.200Z"], to: &session)
        XCTAssertEqual(AgentAttentionSummary.make([session], acknowledged: read).unread, 1)
        let second = session.eventID
        AgentEventParser.applyHook(["session_id": "one", "event": "PermissionRequest", "timestamp": "2026-09-16T12:00:00.200Z"], to: &session)
        XCTAssertEqual(session.eventID, second)
    }
}

final class ClaudeActivityTests: XCTestCase {
    private func row(_ fields: [String: Any], to session: inout AgentSession) {
        ClaudeActivityParser.apply(try! JSONSerialization.data(withJSONObject: fields), to: &session)
    }
    func testPromptToolAnswerAndCompletion() {
        var session = AgentSession(id: "one")
        row(["type": "user", "timestamp": "2026-09-16T12:00:00Z", "uuid": "turn", "cwd": "/work/app", "entrypoint": "cli", "message": ["content": "Fix layout"]], to: &session)
        XCTAssertEqual(session.provider, .claude); XCTAssertEqual(session.surface, .cli)
        XCTAssertEqual(session.userPrompt, "Fix layout"); XCTAssertEqual(session.state, .running)
        row(["type": "assistant", "timestamp": "2026-09-16T12:00:01Z", "message": ["content": [["type": "tool_use", "id": "tool", "name": "Edit", "input": ["file_path": "/work/app/view.swift"]]]]], to: &session)
        XCTAssertTrue(session.toolIsRunning); XCTAssertEqual(session.activityDetail, "/work/app/view.swift")
        row(["type": "user", "timestamp": "2026-09-16T12:00:02Z", "message": ["content": [["type": "tool_result", "tool_use_id": "tool", "content": "done"]]]], to: &session)
        XCTAssertFalse(session.toolIsRunning); XCTAssertEqual(session.userPrompt, "Fix layout")
        row(["type": "system", "subtype": "turn_duration", "timestamp": "2026-09-16T12:00:03Z"], to: &session)
        XCTAssertEqual(session.state, .completed)
        row(["type": "user", "timestamp": "2026-09-16T12:00:00Z", "message": ["content": "Old prompt"]], to: &session)
        XCTAssertEqual(session.state, .completed); XCTAssertEqual(session.userPrompt, "Fix layout")
    }
    func testMetadataAndSubagentsDoNotStartTask() {
        var session = AgentSession(id: "one")
        row(["type": "user", "isMeta": true, "timestamp": "2026-09-16T12:00:00Z", "message": ["content": "system context"]], to: &session)
        XCTAssertEqual(session.state, .unknown); XCTAssertTrue(session.userPrompt.isEmpty)
        row(["type": "user", "isSidechain": true, "timestamp": "2026-09-16T12:00:00Z"], to: &session)
        XCTAssertTrue(session.excluded)
    }
    func testHookWaitingAndResumeWithoutPersistingPrompt() {
        var session = AgentSession(id: "one", state: .running)
        ClaudeActivityParser.applyHook(["session_id": "one", "event": "PermissionRequest", "timestamp": "2026-09-16T12:00:01Z"], to: &session)
        XCTAssertEqual(session.state, .waiting)
        ClaudeActivityParser.applyHook(["session_id": "one", "event": "PostToolUse", "timestamp": "2026-09-16T12:00:02Z"], to: &session)
        XCTAssertEqual(session.state, .running)
        ClaudeActivityParser.applyHook(["session_id": "one", "event": "Notification", "timestamp": "2026-09-16T12:00:03Z"], to: &session)
        XCTAssertEqual(session.state, .running)
        ClaudeActivityParser.applyHook(["session_id": "one", "event": "Stop", "timestamp": "2026-09-16T12:00:04Z"], to: &session)
        XCTAssertEqual(session.state, .running, "Stop handlers can continue a response")
    }
    func testClaudeHookPreservesSettingsAndRemovesOnlyOwnHandlers() throws {
        let original = Data(#"{"model":"custom","hooks":{"Stop":[{"hooks":[{"type":"command","command":"existing"}]}]}}"#.utf8)
        let installed = try AgentHookConfiguration.updating(original, helper: "/helper", eventDirectory: "/events", provider: .claude)
        let object = try JSONSerialization.jsonObject(with: installed) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]
        XCTAssertNil(hooks["Interrupt"]); XCTAssertNotNil(hooks["SessionEnd"])
        let removed = try AgentHookConfiguration.updating(installed, helper: nil, eventDirectory: "/events", provider: .claude)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: original) as! NSDictionary, try JSONSerialization.jsonObject(with: removed) as! NSDictionary)
    }
    func testRepositoryReadsIncrementalLocalRecordsAndReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("projects/project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent(UUID().uuidString + ".jsonl")
        let now = Date()
        func line(_ prompt: String, _ at: Date) throws -> Data {
            var data = try JSONSerialization.data(withJSONObject: ["type": "user", "timestamp": at.ISO8601Format(), "uuid": prompt, "cwd": "/work/demo", "entrypoint": "cli", "message": ["content": prompt]])
            data.append(10); return data
        }
        try line("First", now).write(to: file)
        let repository = ClaudeActivityRepository(home: root, hooks: root.appendingPathComponent("events"))
        let first = await repository.scan(now: now, force: true)
        XCTAssertEqual(first.sessions.first?.userPrompt, "First")
        let again = await repository.scan(now: now)
        XCTAssertEqual(first.sessions, again.sessions)
        try line("Replacement", now.addingTimeInterval(1)).write(to: file, options: .atomic)
        let replaced = await repository.scan(now: now.addingTimeInterval(1))
        XCTAssertEqual(replaced.sessions.first?.userPrompt, "Replacement")
        XCTAssertEqual(replaced.sessions.first?.projectName, "demo")
    }
}
