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
    func testPrimaryStateAndBadgeCountShareOneMeaning() {
        let failed = AgentSession(id: "failure", state: .failed)
        let working = (0..<3).map { AgentSession(id: "run-\($0)", state: .running) }
        let summary = AgentAttentionSummary.make(working + [failed], acknowledged: [:])
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.primaryState, .failed)
        XCTAssertEqual(summary.primaryCount, 1)
        let read = AgentAttentionSummary.make(working + [failed], acknowledged: [failed.identity: failed.eventID])
        XCTAssertEqual(read.primaryState, .running)
        XCTAssertEqual(read.primaryCount, 3)
    }
    func testWaitingKeepsPriorityAfterReadingAndNewFailuresTakeOver() {
        let waiting = AgentSession(id: "waiting", state: .waiting)
        let working = AgentSession(id: "running", state: .running)
        let failed = AgentSession(id: "failure", state: .failed)
        let read = [waiting.identity: waiting.eventID]
        let summary = AgentAttentionSummary.make([working, waiting], acknowledged: read)
        XCTAssertEqual(summary.primaryState, .waiting)
        XCTAssertEqual(summary.primaryCount, 1)
        XCTAssertEqual(summary.unread, 0)
        XCTAssertEqual(AgentAttentionSummary.make([working, waiting, failed], acknowledged: read).primaryState, .failed)
    }
    func testLatestRecordWinsAndReadCompletionStopsContributing() {
        var old = AgentSession(id: "one", state: .failed, updatedAt: Date(timeIntervalSince1970: 1))
        var latest = old; latest.state = .completed; latest.updatedAt = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(AgentAttentionSummary.make([old, latest], acknowledged: [:]).primaryState, .completed)
        XCTAssertEqual(AgentAttentionSummary.make([old, latest], acknowledged: [latest.identity: latest.eventID]).primaryCount, 0)
        old.id = "two"; old.state = .interrupted; old.updatedAt = Date(timeIntervalSince1970: 3)
        XCTAssertEqual(AgentAttentionSummary.make([latest, old], acknowledged: [:]).primaryState, .interrupted)
    }
    func testMotionHasTwoBouncesAQuietIntervalAndBoundedGeometry() {
        XCTAssertLessThan(AgentGlyphMotion.waitingOffset(at: 0.11), -1)
        XCTAssertLessThan(AgentGlyphMotion.waitingOffset(at: 0.43), -0.8)
        for t in stride(from: 0.6, through: 3.59, by: 0.1) { XCTAssertEqual(AgentGlyphMotion.waitingOffset(at: t), 0) }
        for t in stride(from: 0.0, through: 7.2, by: 0.01) {
            XCTAssertLessThanOrEqual(abs(AgentGlyphMotion.pageX(at: t)), 1.6)
            XCTAssertLessThanOrEqual(abs(AgentGlyphMotion.pageY(at: t)), 1.4)
            XCTAssertGreaterThanOrEqual(AgentGlyphMotion.waitingOffset(at: t), -1.5)
            XCTAssertEqual(AgentGlyphMotion.waitingOffset(at: t), AgentGlyphMotion.waitingOffset(at: t + 3.6), accuracy: 0.00001)
        }
        XCTAssertEqual(AgentGlyphMotion.pageX(at: 0), AgentGlyphMotion.pageX(at: 1.8), accuracy: 0.00001)
        XCTAssertEqual(AgentGlyphMotion.pageY(at: 0), AgentGlyphMotion.pageY(at: 1.8), accuracy: 0.00001)
        XCTAssertGreaterThan(AgentGlyphMotion.completionSpread(at: 0), AgentGlyphMotion.completionSpread(at: 0.2))
        XCTAssertEqual(AgentGlyphMotion.completionSpread(at: 0.35), AgentGlyphMotion.completionSpread(at: 100))
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

final class AgentCurrentSessionsTests: XCTestCase {
    func testNewTurnReplacesOldResultWithoutMergingProjectsOrProviders() {
        let old = AgentSession(id: "one", state: .completed, turnID: "old", updatedAt: Date(timeIntervalSince1970: 1))
        var current = old; current.state = .running; current.turnID = "new"; current.updatedAt = Date(timeIntervalSince1970: 2)
        var other = old; other.id = "two"
        var claude = current; claude.provider = .claude
        let latest = AgentCurrentSessions.latest([current, old, other, claude])
        XCTAssertEqual(latest.count, 3)
        XCTAssertEqual(latest.first { $0.identity == current.identity }, current)
    }
    func testHistoryWindowsKeepRecentRecordsAndAlwaysKeepActiveTasks() {
        let now = Date(timeIntervalSince1970: 100000)
        XCTAssertEqual(AgentHistoryWindow.defaultValue, .fiveHours)
        for window in AgentHistoryWindow.allCases {
            for state in AgentRunState.allCases {
                var session = AgentSession(id: "one", state: state, updatedAt: now.addingTimeInterval(-window.duration))
                XCTAssertTrue(AgentCurrentSessions.includes(session, now: now, window: window))
                session.updatedAt = session.updatedAt.addingTimeInterval(-1)
                XCTAssertEqual(AgentCurrentSessions.includes(session, now: now, window: window), state.isActive)
            }
        }
    }
    func testReadingRetentionOnlyExtendsTheCurrentRecordAtExpiry() {
        let now = Date(timeIntervalSince1970: 100000)
        var session = AgentSession(id: "one", state: .completed, turnID: "old", updatedAt: now.addingTimeInterval(-6 * 3600))
        let read = [session.identity: session.eventID]
        XCTAssertTrue(AgentCurrentSessions.includes(session, now: now, window: .fiveHours, retained: read))
        XCTAssertFalse(AgentCurrentSessions.includes(session, now: now, window: .fiveHours))
        XCTAssertTrue(AgentCurrentSessions.includes(session, now: now, window: .oneDay))
        session.turnID = "new"
        XCTAssertFalse(AgentCurrentSessions.includes(session, now: now, window: .fiveHours, retained: read))
    }
}

final class AgentTaskOnlySummaryTests: XCTestCase {
    func testIconPriorityAndRecentListAreIndependent() {
        let failed = AgentSession(id: "error", state: .failed, updatedAt: Date(timeIntervalSince1970: 1))
        let running = AgentSession(id: "working", state: .running, updatedAt: Date(timeIntervalSince1970: 2))
        let waiting = AgentSession(id: "waiting", state: .waiting, updatedAt: Date(timeIntervalSince1970: 3))
        let done = AgentSession(id: "done", state: .completed, updatedAt: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(AgentTaskOnlySummary.emphasis([done, waiting, running, failed]), failed)
        XCTAssertEqual(AgentTaskOnlySummary.emphasis([done, waiting, running]), waiting)
        XCTAssertEqual(AgentTaskOnlySummary.emphasis([waiting, done]), waiting)
        XCTAssertEqual(AgentTaskOnlySummary.recent([failed, running, waiting, done]), [done, waiting])
    }
    func testRecentListHasOnlyCurrentRecordPerConversation() {
        let old = AgentSession(id: "one", state: .completed, updatedAt: Date(timeIntervalSince1970: 1))
        var new = old; new.state = .running; new.updatedAt = Date(timeIntervalSince1970: 2)
        XCTAssertEqual(AgentTaskOnlySummary.recent([old, new]), [new])
        XCTAssertTrue(AgentTaskOnlySummary.recent([]).isEmpty)
    }
}
