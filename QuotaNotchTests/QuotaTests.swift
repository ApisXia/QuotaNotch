import XCTest
@testable import QuotaNotchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let fixtureNow = Date(timeIntervalSince1970: 1_789_400_000)
private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json")))
}

final class QuotaParserTests: XCTestCase {
    func testClaudeStatusLineRateLimits() throws {
        let result = try QuotaParser.parse(fixture("claude"), provider: .claude, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(result.windows.map(\.remainingPercent), [58, 24.5])
        XCTAssertEqual(result.windows[0].resetsAt, Date(timeIntervalSince1970: 1_789_401_600))
        XCTAssertEqual(result.fetchedAt, fixtureNow)
    }

    func testClaudeWindowPastItsResetCountsAsUnused() throws {
        let data = Data(#"{"five_hour":{"used_percentage":90,"resets_at":1789399000},"seven_day":{"used_percentage":10}}"#.utf8)
        let result = try QuotaParser.parse(data, provider: .claude, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [100, 90])
        XCTAssertNil(result.windows[0].resetsAt)
        XCTAssertNil(result.windows[1].resetsAt)
    }

    func testCodexActualDurationsAndResets() throws {
        let result = try QuotaParser.parse(fixture("codex"), provider: .codex, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [73, 9])
        XCTAssertEqual(result.windows.map(\.title), ["5 小时", "7 天"])
        XCTAssertEqual(result.windows[1].resetsAt, fixtureNow.addingTimeInterval(7200))
        // Credits in the fixture must not produce an invented budget/cost window.
        XCTAssertEqual(result.windows.count, 2)
    }

    func testMissingQuotaIsNotUnlimited() {
        for body in ["{}", "{\"rate_limit\":null}", "[]", "not json"] {
            XCTAssertThrowsError(try QuotaParser.parse(Data(body.utf8), provider: .codex, now: fixtureNow))
        }
    }

    func testRejectsBooleanNegativeOverHundredAndStringPercent() {
        // 1789400000 guards against the epoch-instead-of-percentage value early in a window.
        for value in ["true", "-1", "101", "\"42\"", "null", "1789400000"] {
            let data = Data("{\"five_hour\":{\"used_percentage\":\(value)}}".utf8)
            XCTAssertThrowsError(try QuotaParser.parse(data, provider: .claude, now: fixtureNow))
        }
    }

    func testValidZeroAndUnknownReset() throws {
        let data = Data(#"{"five_hour":{"used_percentage":100,"resets_at":"bad"},"seven_day":{"used_percentage":0}}"#.utf8)
        let result = try QuotaParser.parse(data, provider: .claude, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [0, 100])
        XCTAssertNil(result.windows[0].resetsAt)
    }

    func testUnknownDurationIsNotAssumedWeekly() throws {
        let data = Data(#"{"rate_limit":{"secondary_window":{"used_percent":10}}}"#.utf8)
        let result = try QuotaParser.parse(data, provider: .codex, now: fixtureNow)
        XCTAssertEqual(result.windows.first?.title, "次窗口")
        XCTAssertNil(result.windows.first?.resetsAt)
    }

    func testAPIKeyDoesNotMasqueradeAsOAuth() {
        let data = Data(#"{"OPENAI_API_KEY":"fixture-not-a-real-key"}"#.utf8)
        XCTAssertThrowsError(try LocalQuotaCredentials.decode(data, provider: .codex))
    }

    func testCredentialDescriptionIsRedacted() throws {
        let data = Data(#"{"tokens":{"access_token":"fixture-token","account_id":"fixture-account"}}"#.utf8)
        let credential = try LocalQuotaCredentials.decode(data, provider: .codex)
        XCTAssertFalse(String(describing: credential).contains("fixture-token"))
        XCTAssertFalse(String(reflecting: credential).contains("fixture-token"))
        XCTAssertEqual(credential.accountID, "fixture-account")
    }

    func testRetryAfterSecondsDateAndMalformed() {
        XCTAssertEqual(QuotaClient.retryDate("3600", now: fixtureNow), fixtureNow.addingTimeInterval(3600))
        XCTAssertEqual(QuotaClient.retryDate("0", now: fixtureNow), fixtureNow.addingTimeInterval(60))
        XCTAssertEqual(QuotaClient.retryDate("bad", now: fixtureNow), fixtureNow.addingTimeInterval(900))
        let parsed = QuotaClient.retryDate("Wed, 01 Jan 2031 00:00:00 GMT", now: fixtureNow)
        XCTAssertEqual(parsed, QuotaParser.isoDate("2031-01-01T00:00:00Z"))
    }
}

private struct TestCredentials: QuotaCredentialSource {
    var error: QuotaFailure?
    var expiry: Date?
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        if let error { throw error }
        return QuotaCredential(accessToken: "fixture-token", accountID: "fixture-account", expiresAt: expiry)
    }
}

private actor TestTransport: QuotaTransport {
    var responses: [QuotaHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [QuotaHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> QuotaHTTPResponse {
        requests.append(request)
        // Yield while the actor is reentrant, exercising concurrent refresh coalescing.
        try await Task.sleep(nanoseconds: 10_000_000)
        guard !responses.isEmpty else { throw QuotaFailure.network }
        return responses.removeFirst()
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = fixtureNow
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

final class QuotaClientTests: XCTestCase {
    func testConcurrentRequestsAndManualRefreshShareCooldown() async throws {
        let transport = TestTransport([QuotaHTTPResponse(data: try fixture("codex"), status: 200, retryAfter: nil)])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { fixtureNow })
        async let first = client.refresh(.codex)
        async let second = client.refresh(.codex)
        let pair = await (first, second)
        XCTAssertEqual(pair.0.snapshot, pair.1.snapshot)
        _ = await client.refresh(.codex)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.host, "chatgpt.com")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "fixture-account")
    }

    func testNotLoggedInAndExpiredNeverSendRequest() async {
        let transport = TestTransport([])
        for credentials in [TestCredentials(error: .notSignedIn), TestCredentials(expiry: fixtureNow.addingTimeInterval(-1))] {
            let client = QuotaClient(credentials: credentials, transport: transport, clock: { fixtureNow })
            let result = await client.refresh(.codex)
            XCTAssertNotNil(result.failure)
            XCTAssertNil(result.snapshot)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 0)
    }

    func testRateLimitPreventsEarlyRetry() async {
        let transport = TestTransport([QuotaHTTPResponse(data: Data(), status: 429, retryAfter: "3600")])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { fixtureNow })
        let first = await client.refresh(.codex)
        XCTAssertEqual(first.nextAttempt, fixtureNow.addingTimeInterval(3600))
        _ = await client.refresh(.codex)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testNetworkFailureKeepsExplicitlyStaleSnapshotBut401ClearsIt() async throws {
        let clock = TestClock()
        let transport = TestTransport([
            QuotaHTTPResponse(data: try fixture("codex"), status: 200, retryAfter: nil),
            QuotaHTTPResponse(data: Data("private-error-body".utf8), status: 503, retryAfter: nil),
            QuotaHTTPResponse(data: Data(), status: 401, retryAfter: nil)
        ])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { clock.now() })
        let good = await client.refresh(.codex)
        clock.advance(301)
        let stale = await client.refresh(.codex)
        XCTAssertEqual(stale.snapshot, good.snapshot)
        XCTAssertEqual(stale.failure, .http(503))
        XCTAssertFalse(stale.failure!.message.contains("private-error-body"))
        clock.advance(61)
        let expired = await client.refresh(.codex)
        XCTAssertNil(expired.snapshot)
        XCTAssertEqual(expired.failure, .expired)
    }

    func testProvidersHaveIndependentSchedules() async throws {
        let transport = TestTransport([QuotaHTTPResponse(data: try fixture("codex"), status: 200, retryAfter: nil)])
        let usage = FixtureUsage(.success(try QuotaParser.parse(fixture("claude"), provider: .claude, now: fixtureNow)))
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { fixtureNow }, claudeUsage: usage)
        let claude = await client.refresh(.claude)
        let codex = await client.refresh(.codex)
        XCTAssertEqual(claude.nextAttempt, fixtureNow.addingTimeInterval(30))
        XCTAssertEqual(codex.nextAttempt, fixtureNow.addingTimeInterval(300))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "Claude never makes a network request")
    }

    func testTransientFailuresBackOffAndSuccessResets() async throws {
        let clock = TestClock()
        let transport = TestTransport([
            QuotaHTTPResponse(data: Data(), status: 503, retryAfter: nil),
            QuotaHTTPResponse(data: Data(), status: 503, retryAfter: nil),
            QuotaHTTPResponse(data: Data(), status: 503, retryAfter: nil),
            QuotaHTTPResponse(data: try fixture("codex"), status: 200, retryAfter: nil),
            QuotaHTTPResponse(data: Data(), status: 503, retryAfter: nil)
        ])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { clock.now() })
        var waits: [TimeInterval] = []
        for _ in 0..<5 {
            let result = await client.refresh(.codex)
            waits.append(result.nextAttempt.timeIntervalSince(clock.now()))
            clock.advance(result.nextAttempt.timeIntervalSince(clock.now()))
        }
        XCTAssertEqual(waits, [60, 120, 240, 300, 60])
    }

    func testForbiddenIsNotTreatedAsLoggedOut() async throws {
        let clock = TestClock()
        let transport = TestTransport([
            QuotaHTTPResponse(data: try fixture("codex"), status: 200, retryAfter: nil),
            QuotaHTTPResponse(data: Data(), status: 403, retryAfter: nil)
        ])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { clock.now() })
        let good = await client.refresh(.codex)
        clock.advance(301)
        let blocked = await client.refresh(.codex)
        XCTAssertEqual(blocked.failure, .http(403))
        XCTAssertEqual(blocked.snapshot, good.snapshot)
    }

    func testClaudeWithoutStatusLineIsNotConnectedAndRetriesLocally() async {
        let client = QuotaClient(credentials: TestCredentials(), transport: TestTransport([]), clock: { fixtureNow },
                                 claudeUsage: FixtureUsage(.failure(.notConnected)), claudeFallback: FixtureFallback())
        let result = await client.refresh(.claude)
        XCTAssertEqual(result.failure, .notConnected)
        XCTAssertEqual(result.nextAttempt, fixtureNow.addingTimeInterval(30))
    }

    func testOnlyManualClaudeRefreshUsesTheCLIFallback() async {
        let fallback = FixtureFallback()
        let clock = TestClock()
        let client = QuotaClient(credentials: TestCredentials(), transport: TestTransport([]), clock: { clock.now() },
                                 claudeUsage: FixtureUsage(.failure(.notConnected)), claudeFallback: fallback)
        _ = await client.refresh(.claude)
        let scheduledCalls = await fallback.calls
        XCTAssertEqual(scheduledCalls, 0)
        clock.advance(30)
        let manual = await client.refresh(.claude, manual: true)
        XCTAssertNil(manual.failure)
        XCTAssertEqual(manual.snapshot?.windows.first?.remainingPercent, 75)
        let manualCalls = await fallback.calls
        XCTAssertEqual(manualCalls, 1)
    }

    func testManualRefreshKeepsRecentStatusLineReading() async throws {
        let fallback = FixtureFallback()
        let reading = try QuotaParser.parse(fixture("claude"), provider: .claude, now: fixtureNow)
        let client = QuotaClient(credentials: TestCredentials(), transport: TestTransport([]), clock: { fixtureNow },
                                 claudeUsage: FixtureUsage(.success(reading)), claudeFallback: fallback)
        let result = await client.refresh(.claude, manual: true)
        XCTAssertEqual(result.snapshot, reading)
        let calls = await fallback.calls
        XCTAssertEqual(calls, 0)
    }
}

private struct FixtureUsage: ClaudeUsageSource {
    let result: Result<QuotaSnapshot, QuotaFailure>
    init(_ result: Result<QuotaSnapshot, QuotaFailure>) { self.result = result }
    func latest(now: Date) async throws -> QuotaSnapshot { try result.get() }
}

private actor FixtureFallback: ClaudeQuotaFallback {
    private(set) var calls = 0
    func fetch(now: Date) async throws -> QuotaSnapshot {
        calls += 1
        let window = QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: 75, resetsAt: nil)
        return QuotaSnapshot(windows: [window], fetchedAt: now)
    }
}
