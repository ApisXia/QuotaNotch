import XCTest
@testable import QuotaNotchCore

#if os(macOS)
private final class RecordingClaudeSecurityRunner: ClaudeSecurityCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [ClaudeSecurityCommandResult] = []
    private(set) var calls: [[String]] = []

    init(_ results: [ClaudeSecurityCommandResult]) {
        queued = results
    }

    func run(arguments: [String]) throws -> ClaudeSecurityCommandResult {
        lock.lock()
        defer { lock.unlock() }
        calls.append(arguments)
        guard !queued.isEmpty else {
            return ClaudeSecurityCommandResult(terminationStatus: 51, standardOutput: Data(),
                                               standardError: Data("fixture exhausted secret".utf8))
        }
        return queued.removeFirst()
    }
}

private func commandResult(_ status: Int32 = 0, output: String = "", error: String = "") -> ClaudeSecurityCommandResult {
    ClaudeSecurityCommandResult(terminationStatus: status, standardOutput: Data(output.utf8),
                                standardError: Data(error.utf8))
}

private func credentialPayload(_ token: String) -> String {
    #"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"refresh","expiresAt":4102444800000}}"#
}

final class ClaudeKeychainIOTests: XCTestCase {
    func testReadUsesExplicitAccountAndNeverCallsNativeKeychain() throws {
        let payload = credentialPayload("fixture")
        let runner = RecordingClaudeSecurityRunner([commandResult(output: payload + "\n")])
        let io = SystemClaudeKeychainIO(runner: runner, account: "fixture-user")

        XCTAssertEqual(try io.read(service: "Claude Code-credentials"), Data(payload.utf8))
        XCTAssertEqual(runner.calls, [["find-generic-password", "-s", "Claude Code-credentials",
                                       "-a", "fixture-user", "-w"]])
    }

    func testHexEncodedSecurityOutputIsDecoded() throws {
        let payload = credentialPayload("hex-fixture")
        let hex = Data(payload.utf8).map { String(format: "%02x", $0) }.joined()
        let runner = RecordingClaudeSecurityRunner([commandResult(output: hex + "\n")])
        let io = SystemClaudeKeychainIO(runner: runner, account: "fixture-user")

        XCTAssertEqual(try io.read(service: "Claude Code-credentials"), Data(payload.utf8))
    }

    func testMalformedKeychainPayloadIsUnavailable() {
        let runner = RecordingClaudeSecurityRunner([commandResult(output: "{\"unexpected\":true}\n")])
        let io = SystemClaudeKeychainIO(runner: runner, account: "fixture-user")

        XCTAssertThrowsError(try io.read(service: "Claude Code-credentials")) { error in
            XCTAssertEqual(error as? QuotaFailure, .credentialsUnavailable)
        }
    }

    func testDeniedReadIsUnavailableAndMissingItemIsNotSignedIn() {
        let denied = SystemClaudeKeychainIO(
            runner: RecordingClaudeSecurityRunner([commandResult(51, error: "secret keychain details")]),
            account: "fixture-user"
        )
        XCTAssertThrowsError(try denied.read(service: "Claude Code-credentials")) { error in
            XCTAssertEqual(error as? QuotaFailure, .credentialsUnavailable)
            XCTAssertFalse(String(describing: error).contains("secret"))
        }

        let missing = SystemClaudeKeychainIO(
            runner: RecordingClaudeSecurityRunner([commandResult(44, error: "missing item details")]),
            account: "fixture-user"
        )
        XCTAssertThrowsError(try missing.read(service: "Claude Code-credentials")) { error in
            XCTAssertEqual(error as? QuotaFailure, .notSignedIn)
        }
    }

    func testReplaceUsesInPlaceUpdateAndCompactJSONWithoutACLArguments() throws {
        let old = Data("{\n  \"claudeAiOauth\": {\n    \"accessToken\": \"old\"\n  }\n}".utf8)
        let updated = Data("{\n  \"claudeAiOauth\": {\n    \"accessToken\": \"new\"\n  }\n}".utf8)
        let runner = RecordingClaudeSecurityRunner([
            commandResult(output: String(decoding: old, as: UTF8.self)),
            commandResult(),
            commandResult(output: String(decoding: updated, as: UTF8.self))
        ])
        let io = SystemClaudeKeychainIO(runner: runner, account: "fixture-user")

        XCTAssertEqual(try io.replace(service: "Claude Code-credentials", expected: old, updated: updated), updated)
        XCTAssertEqual(runner.calls.count, 3)
        let write = runner.calls[1]
        XCTAssertEqual(Array(write.prefix(6)), ["add-generic-password", "-U", "-s", "Claude Code-credentials",
                                                "-a", "fixture-user"])
        XCTAssertEqual(write[6], "-w")
        XCTAssertFalse(write.contains("delete-generic-password"))
        XCTAssertFalse(write.contains("-T"))
        XCTAssertFalse(write.contains("-A"))
        XCTAssertFalse(write[7].contains("\n"))
        XCTAssertFalse(write[7].contains("\r"))
        XCTAssertTrue(write[7].contains("\"accessToken\":\"new\""))
    }

    func testReplaceDoesNotWriteAfterCompareMismatch() throws {
        let current = Data(credentialPayload("current").utf8)
        let runner = RecordingClaudeSecurityRunner([commandResult(output: credentialPayload("current"))])
        let io = SystemClaudeKeychainIO(runner: runner, account: "fixture-user")

        let result = try io.replace(service: "Claude Code-credentials", expected: Data(credentialPayload("old").utf8),
                                    updated: Data(credentialPayload("new").utf8))
        XCTAssertEqual(result, current)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testValidFileDoesNotTouchKeychainFixture() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quotanotch-keychain-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".credentials.json")
        let payload = credentialPayload("file-first")
        try Data(payload.utf8).write(to: file)

        let runner = RecordingClaudeSecurityRunner([])
        let io = SystemClaudeCredentialIO(keychain: SystemClaudeKeychainIO(runner: runner, account: "fixture-user"))
        let repo = ClaudeCredentialRepository(io: io, environment: ["CLAUDE_CONFIG_DIR": folder.path],
                                              now: { Date(timeIntervalSince1970: 1_700_000_000) })

        XCTAssertEqual(try repo.load().accessToken, "file-first")
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCommandRunnerCapsOutputAndDrainsBothPipes() throws {
        let script = try makeExecutable(contents: "#!/bin/sh\ndd if=/dev/zero bs=1024 count=256 2>/dev/null\ndd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemClaudeSecurityCommandRunner(executableURL: script, timeout: 2, outputLimit: 1_024)

        XCTAssertThrowsError(try runner.run(arguments: [])) { error in
            XCTAssertEqual(error as? ClaudeSecurityCommandError, .outputLimitExceeded)
        }
    }

    func testCommandRunnerTerminatesTimedOutChild() throws {
        let script = try makeExecutable(contents: "#!/bin/sh\nsleep 10 &\nchild=$!\ntrap 'kill $child 2>/dev/null; exit 0' TERM INT\nwait $child\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = SystemClaudeSecurityCommandRunner(executableURL: script, timeout: 0.1, outputLimit: 1_024)
        let started = Date()

        XCTAssertThrowsError(try runner.run(arguments: [])) { error in
            XCTAssertEqual(error as? ClaudeSecurityCommandError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    private func makeExecutable(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quotanotch-security-fixture-\(UUID().uuidString)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
#endif
