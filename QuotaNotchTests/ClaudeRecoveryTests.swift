import XCTest
@testable import QuotaNotchCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let instant = Date(timeIntervalSince1970: 1_789_400_000)
private func login(_ token: String = "old", expiry: TimeInterval = -1, refresh: String? = "refresh") -> QuotaCredential {
    QuotaCredential(accessToken: token, accountID: nil, expiresAt: instant.addingTimeInterval(expiry), refreshToken: refresh)
}
private func reply(_ status: Int = 200, _ body: String = #"{"five_hour":{"utilization":25},"seven_day":{"utilization":50}}"#,
                   retry: String? = nil) -> QuotaHTTPResponse {
    QuotaHTTPResponse(data: Data(body.utf8), status: status, retryAfter: retry)
}
private let renewal = #"{"access_token":"new","refresh_token":"rotated","expires_in":3600}"#

private actor RecoveryCredentials: QuotaCredentialSource {
    var values: [QuotaCredential]
    var saveError: QuotaFailure?
    private(set) var saved: [QuotaCredential] = []
    init(_ values: [QuotaCredential], saveError: QuotaFailure? = nil) { self.values = values; self.saveError = saveError }
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        if values.count > 1 { return values.removeFirst() }
        return values[0]
    }
    func saveClaude(_ updated: QuotaCredential, replacing original: QuotaCredential) async throws -> QuotaCredential {
        if let saveError { throw saveError }
        saved.append(updated); values = [updated]; return updated
    }
}
private actor RecoveryTransport: QuotaTransport {
    var replies: [QuotaHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [QuotaHTTPResponse]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> QuotaHTTPResponse {
        requests.append(request)
        try await Task.sleep(nanoseconds: 1_000_000)
        guard !replies.isEmpty else { throw QuotaFailure.network }
        return replies.removeFirst()
    }
}
private actor RecoveryFallback: ClaudeQuotaFallback {
    private(set) var calls = 0
    let error: QuotaFailure?
    init(error: QuotaFailure? = nil) { self.error = error }
    func fetch(now: Date) async throws -> QuotaSnapshot {
        calls += 1
        if let error { throw error }
        return try QuotaParser.parse(reply().data, provider: .claude, now: now)
    }
}

final class ClaudeRecoveryTests: XCTestCase {
    func testExpiredTokenRenewsPersistsAndUsesNewTokenOnceForConcurrentCallers() async throws {
        let credentials = RecoveryCredentials([login()])
        let transport = RecoveryTransport([reply(200, renewal), reply()])
        let client = QuotaClient(credentials: credentials, transport: transport, clock: { instant })
        async let a = client.refresh(.claude)
        async let b = client.refresh(.claude)
        let pair = await (a, b)
        XCTAssertNil(pair.0.failure)
        XCTAssertEqual(pair.0.snapshot, pair.1.snapshot)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://platform.claude.com/v1/oauth/token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: String])
        XCTAssertEqual(body["grant_type"], "refresh_token")
        XCTAssertEqual(body["refresh_token"], "refresh")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        let saved = await credentials.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.refreshToken, "rotated")
        XCTAssertEqual(saved.first?.expiresAt, instant.addingTimeInterval(3600))
        XCTAssertFalse(String(reflecting: saved[0]).contains("rotated"))
    }

    func testRefreshesWithinFiveMinutes() async throws {
        let credentials = RecoveryCredentials([login(expiry: 299)])
        let transport = RecoveryTransport([reply(200, renewal), reply()])
        _ = try await ClaudeQuotaProbe(credentials: credentials, transport: transport, clock: { instant }).fetch()
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.httpMethod, "POST")
    }

    func test401RenewsAndRetriesOnlyOnce() async throws {
        let credentials = RecoveryCredentials([login(expiry: 3600)])
        let transport = RecoveryTransport([reply(401), reply(200, renewal), reply(401)])
        let client = QuotaClient(credentials: credentials, transport: transport, clock: { instant })
        let result = await client.refresh(.claude)
        XCTAssertEqual(result.failure, .expired)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
    }

    func test401UsesExternallyUpdatedTokenWithoutRotatingIt() async throws {
        let credentials = RecoveryCredentials([login(expiry: 3600), login("external", expiry: 7200)])
        let transport = RecoveryTransport([reply(401), reply()])
        _ = try await ClaudeQuotaProbe(credentials: credentials, transport: transport, clock: { instant }).fetch()
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer external")
    }

    func testFailedRefreshRecoversCredentialsUpdatedDuringRequest() async throws {
        let credentials = RecoveryCredentials([login(), login(), login("external", expiry: 7200)])
        let transport = RecoveryTransport([reply(400, #"{"error":"invalid_grant"}"#), reply()])
        _ = try await ClaudeQuotaProbe(credentials: credentials, transport: transport, clock: { instant }).fetch()
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer external")
    }

    func testAlreadyUpdatedCredentialSkipsRefresh() async throws {
        let credentials = RecoveryCredentials([login(), login("external", expiry: 7200)])
        let transport = RecoveryTransport([reply()])
        _ = try await ClaudeQuotaProbe(credentials: credentials, transport: transport, clock: { instant }).fetch()
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "GET")
    }

    func testRateLimitBlocksFallbackAndKeepsServerCooldown() async throws {
        for expiry: TimeInterval in [-1, 3600] {
            let credentials = RecoveryCredentials([login(expiry: expiry)])
            let fallback = RecoveryFallback()
            let client = QuotaClient(credentials: credentials, transport: RecoveryTransport([reply(429, "", retry: "3600")]),
                clock: { instant }, claudeFallback: fallback)
            let result = await client.refresh(.claude)
            XCTAssertEqual(result.nextAttempt, instant.addingTimeInterval(3600))
            let calls = await fallback.calls
            XCTAssertEqual(calls, 0)
        }
    }

    func testAuthenticationFailureUsesCLIFallback() async throws {
        let fallback = RecoveryFallback()
        let client = QuotaClient(credentials: RecoveryCredentials([login()]),
            transport: RecoveryTransport([reply(400)]), clock: { instant }, claudeFallback: fallback)
        let result = await client.refresh(.claude)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.snapshot?.windows.first?.remainingPercent, 75)
        let calls = await fallback.calls
        XCTAssertEqual(calls, 1)
    }

    func testFallbackRateLimitIsNotHiddenByAuthenticationError() async {
        let until = instant.addingTimeInterval(900)
        let client = QuotaClient(credentials: RecoveryCredentials([login(refresh: nil)]),
            transport: RecoveryTransport([]), clock: { instant }, claudeFallback: RecoveryFallback(error: .rateLimited(until)))
        let result = await client.refresh(.claude)
        XCTAssertEqual(result.failure, .rateLimited(until))
    }

    func testPersistenceFailureDoesNotPretendRefreshWasSaved() async {
        let client = QuotaClient(credentials: RecoveryCredentials([login()], saveError: .credentialsUnavailable),
            transport: RecoveryTransport([reply(200, renewal)]), clock: { instant })
        let result = await client.refresh(.claude)
        XCTAssertEqual(result.failure, .credentialsUnavailable)
    }

    func testMalformedRefreshResponseCannotOverwriteCredentials() async {
        for body in [#"{"access_token":"bad\ntoken","expires_in":3600}"#, #"{"access_token":"new","expires_in":-1}"#] {
            let credentials = RecoveryCredentials([login()])
            let client = QuotaClient(credentials: credentials, transport: RecoveryTransport([reply(200, body)]), clock: { instant })
            let result = await client.refresh(.claude)
            XCTAssertEqual(result.failure, .invalidResponse)
            let saved = await credentials.saved
            XCTAssertTrue(saved.isEmpty)
        }
    }
}

private final class MemoryCredentialIO: ClaudeCredentialIO, @unchecked Sendable {
    let lock = NSLock()
    var file: Data?
    var keychain: Data?
    var concurrentChange: Data?
    var failFile = false
    func read(_ location: ClaudeCredentialLocation) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if case .file = location {
            if failFile { throw QuotaFailure.credentialsUnavailable }
            guard let file else { throw QuotaFailure.notSignedIn }; return file
        }
        guard let keychain else { throw QuotaFailure.notSignedIn }; return keychain
    }
    func replace(_ location: ClaudeCredentialLocation, expected: Data, updated: Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let concurrentChange { return concurrentChange }
        if case .file = location { file = updated } else { keychain = updated }
        return updated
    }
}
private func credentialJSON(_ token: String, expiry: TimeInterval) -> Data {
    Data("{\"other\":true,\"claudeAiOauth\":{\"accessToken\":\"\(token)\",\"refreshToken\":\"refresh\",\"scopes\":[\"user:profile\"],\"expiresAt\":\((instant.timeIntervalSince1970 + expiry) * 1000)}}".utf8)
}
final class ClaudeCredentialRepositoryTests: XCTestCase {
    func testExpiredMalformedOrUnreadableFileDoesNotHideValidKeychain() throws {
        for variant in 0..<3 {
            let io = MemoryCredentialIO()
            io.file = variant == 0 ? credentialJSON("stale", expiry: -1) : Data("bad".utf8)
            io.failFile = variant == 2
            io.keychain = credentialJSON("current", expiry: 3600)
            let repo = ClaudeCredentialRepository(io: io, now: { instant })
            XCTAssertEqual(try repo.load().accessToken, "current")
        }
    }

    func testSavePreservesScopesAndUnknownFields() throws {
        let io = MemoryCredentialIO(); io.file = credentialJSON("old", expiry: -1)
        let repo = ClaudeCredentialRepository(io: io, now: { instant })
        let original = try repo.load()
        _ = try repo.save(login("new", expiry: 3600), replacing: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(io.file)) as? [String: Any])
        XCTAssertEqual(root["other"] as? Bool, true)
        let oauth = try XCTUnwrap(root["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:profile"])
        XCTAssertEqual(oauth["accessToken"] as? String, "new")
    }

    func testExternalLoginIsNeverOverwrittenByOlderRefresh() throws {
        let io = MemoryCredentialIO(); io.file = credentialJSON("old", expiry: -1)
        let repo = ClaudeCredentialRepository(io: io, now: { instant })
        let original = try repo.load()
        io.file = credentialJSON("external", expiry: 7200)
        let result = try repo.save(login("new", expiry: 3600), replacing: original)
        XCTAssertEqual(result.accessToken, "external")
        XCTAssertEqual(try repo.load().accessToken, "external")
    }

    func testLastMomentChangeIsReturnedInsteadOfOverwritten() throws {
        let io = MemoryCredentialIO(); io.file = credentialJSON("old", expiry: -1)
        io.concurrentChange = credentialJSON("external", expiry: 7200)
        let repo = ClaudeCredentialRepository(io: io, now: { instant })
        let result = try repo.save(login("new", expiry: 3600), replacing: repo.load())
        XCTAssertEqual(result.accessToken, "external")
    }
}

final class ClaudeUsageScreenTests: XCTestCase {
    func testUsedAndLeftPercentagesAndRelativeReset() throws {
        let screen = "Current session\n25% used\nResets in 2h 15m\nCurrent week (all models)\n35% left"
        let result = try ClaudeUsageScreen.parse(screen, now: instant)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [75, 35])
        XCTAssertEqual(result.windows[0].resetsAt, instant.addingTimeInterval(8100))
        XCTAssertNil(result.windows[1].resetsAt)
    }

    func testPromotionalRateLimitTextIsNotAnError() throws {
        let result = try ClaudeUsageScreen.parse("Rate limits are 2x higher this week\nCurrent session\n25% used", now: instant)
        XCTAssertEqual(result.windows.first?.remainingPercent, 75)
        XCTAssertEqual(ClaudeUsageScreen.failure(in: "Error fetching usage: HTTP 429", now: instant),
                       .rateLimited(instant.addingTimeInterval(900)))
        XCTAssertThrowsError(try ClaudeUsageScreen.parse("Current session\n25% used\nauthentication_error", now: instant))
    }

    func testMissingSessionDoesNotBorrowWeeklyPercentage() {
        XCTAssertThrowsError(try ClaudeUsageScreen.parse("Current session\nCurrent week (all models)\n40% used", now: instant))
        XCTAssertThrowsError(try ClaudeUsageScreen.parse("Current session\nLoading usage data\n20% used", now: instant))
        XCTAssertThrowsError(try ClaudeUsageScreen.parse("Current session\n101% used", now: instant))
    }

    func testTerminalRedrawUsesNewPercentage() throws {
        let raw = "\u{1b}[2J\u{1b}[HCurrent session\r\n90% used\u{1b}[2;1H\u{1b}[2K25% used"
        let result = try ClaudeUsageScreen.parse(ClaudeUsageScreen.render(raw), now: instant)
        XCTAssertEqual(result.windows.first?.remainingPercent, 75)
    }

    func testErasedScreenDoesNotRetainOldQuota() {
        let raw = "Current session\n25% used\u{1b}[2J\u{1b}[HLoading usage data"
        XCTAssertThrowsError(try ClaudeUsageScreen.parse(ClaudeUsageScreen.render(raw), now: instant))
    }
}

#if os(macOS)
final class ClaudeCLIProcessTests: XCTestCase {
    private func fixture(_ output: String, timeout: TimeInterval = 2) throws -> (URL, ClaudeCLIQuotaFallback) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("quotanotch-cli-\(UUID().uuidString)")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = "#!/bin/sh\nprintf '%s' '" + output + "'\nwhile read line; do :; done\n"
        let executable = bin.appendingPathComponent("claude")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (home, ClaudeCLIQuotaFallback(environment: ["PATH": bin.path], home: home, timeout: timeout))
    }

    func testReadsPseudoTerminalAndStopsChild() async throws {
        let (home, runner) = try fixture("Current session\n25% used\nCurrent week (all models)\n50% used")
        defer { try? FileManager.default.removeItem(at: home) }
        let result = try await runner.fetch(now: instant)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [75, 50])
    }

    func testTimeoutAndCancellationAreBounded() async throws {
        let (home, runner) = try fixture("", timeout: 0.2)
        defer { try? FileManager.default.removeItem(at: home) }
        let start = Date()
        do { _ = try await runner.fetch(now: instant); XCTFail("Expected timeout") } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        var longRunner = runner; longRunner.timeout = 20
        let cancellable = longRunner
        let task = Task { try await cancellable.fetch(now: instant) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
#endif

#if os(macOS)
final class ClaudeCredentialFileTests: XCTestCase {
    func testAtomicFileWriteIsPrivateAndRejectsStaleReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quotanotch-credentials-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.json")
        let old = credentialJSON("old", expiry: -1), fresh = credentialJSON("fresh", expiry: 3600)
        try old.write(to: file)
        let io = SystemClaudeCredentialIO()
        XCTAssertEqual(try io.replace(.file(file), expected: old, updated: fresh), fresh)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertEqual(try io.replace(.file(file), expected: old, updated: old), fresh)
        XCTAssertEqual(try Data(contentsOf: file), fresh)
    }

    func testCustomCredentialSymlinkTargetsOriginalFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quotanotch-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("fixture.json")
        try credentialJSON("fixture", expiry: 3600).write(to: target)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(".credentials.json"), withDestinationURL: target)
        let repo = ClaudeCredentialRepository(io: MemoryCredentialIO(), environment: ["CLAUDE_CONFIG_DIR": folder.path])
        XCTAssertEqual(repo.locations.first, .file(target.resolvingSymlinksInPath()))
    }
}
#endif
