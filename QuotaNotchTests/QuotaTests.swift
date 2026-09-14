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
    func testClaudeWindowsAndBothDateFormats() throws {
        let result = try QuotaParser.parse(fixture("claude"), provider: .claude, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [58, 25])
        XCTAssertTrue(result.windows.allSatisfy { $0.resetsAt != nil })
        XCTAssertEqual(result.fetchedAt, fixtureNow)
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
        for value in ["true", "-1", "101", "\"42\"", "null"] {
            let data = Data("{\"five_hour\":{\"utilization\":\(value)}}".utf8)
            XCTAssertThrowsError(try QuotaParser.parse(data, provider: .claude, now: fixtureNow))
        }
    }

    func testValidZeroAndUnknownReset() throws {
        let data = Data(#"{"five_hour":{"utilization":100,"resets_at":"bad"},"seven_day":{"utilization":0}}"#.utf8)
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
            let result = await client.refresh(.claude)
            XCTAssertNotNil(result.failure)
            XCTAssertNil(result.snapshot)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 0)
    }

    func testRateLimitPreventsEarlyRetry() async {
        let transport = TestTransport([QuotaHTTPResponse(data: Data(), status: 429, retryAfter: "3600")])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { fixtureNow })
        let first = await client.refresh(.claude)
        XCTAssertEqual(first.nextAttempt, fixtureNow.addingTimeInterval(3600))
        _ = await client.refresh(.claude)
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
        let transport = TestTransport([
            QuotaHTTPResponse(data: try fixture("claude"), status: 200, retryAfter: nil),
            QuotaHTTPResponse(data: try fixture("codex"), status: 200, retryAfter: nil)
        ])
        let client = QuotaClient(credentials: TestCredentials(), transport: transport, clock: { fixtureNow })
        let claude = await client.refresh(.claude)
        let codex = await client.refresh(.codex)
        XCTAssertEqual(claude.nextAttempt, fixtureNow.addingTimeInterval(900))
        XCTAssertEqual(codex.nextAttempt, fixtureNow.addingTimeInterval(300))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }
}
