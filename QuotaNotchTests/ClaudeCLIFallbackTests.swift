import XCTest
@testable import QuotaNotchCore

private let instant = Date(timeIntervalSince1970: 1_789_400_000)

final class ClaudeUsageScreenTests: XCTestCase {
    func testUsedAndLeftPercentagesAndRelativeReset() throws {
        let screen = "Current session\n25% used\nResets in 2h 15m\nCurrent week (all models)\n35% left"
        let result = try ClaudeUsageScreen.parse(screen, now: instant)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [75, 35])
        XCTAssertEqual(result.windows[0].resetsAt, instant.addingTimeInterval(8100))
        XCTAssertNil(result.windows[1].resetsAt)
    }

    /// The /usage screen of current Claude Code versions: clock times with a time zone and a
    /// weekly window per model.
    func testAbsoluteResetsAndModelWeeks() throws {
        let screen = """
        Current session
        ██████████████████          67% used
        Resets 2:10am (Asia/Tokyo)                                       │

        Current week (all models)
        ██                          5% used
        Resets Nov 6 at 11pm (Asia/Tokyo)

        Current week (Fable)
        █                           2% used
        Resets Nov 6 at 10:59pm (Asia/Tokyo)
        """
        let result = try ClaudeUsageScreen.parse(screen, now: instant)
        XCTAssertEqual(result.windows.map(\.id), ["five_hour", "seven_day", "seven_day_fable"])
        XCTAssertEqual(result.windows.map(\.remainingPercent), [33, 95, 98])
        XCTAssertEqual(result.windows.map(\.title).last, "Fable · 7 天")
        XCTAssertEqual(result.windows[0].resetsAt, instant.addingTimeInterval(5800))
        XCTAssertEqual(result.windows[1].resetsAt, instant.addingTimeInterval(4_573_600))
        XCTAssertEqual(result.windows[2].resetsAt, instant.addingTimeInterval(4_573_540))
        XCTAssertEqual(ClaudeUsageScreen.workspaceTrustKeys(onScreen: "Do you trust the files in this folder?"), "y\r")
        XCTAssertEqual(ClaudeUsageScreen.workspaceTrustKeys(onScreen: "Quick safety check\n\n  1. Yes, I trust this folder\n❯ 2. No, exit"), "\u{1b}[A")
        XCTAssertEqual(ClaudeUsageScreen.workspaceTrustKeys(onScreen: "Quick safety check\n\n❯ 1. Yes, I trust this folder\n  2. No, exit"), "\r")
        XCTAssertNil(ClaudeUsageScreen.workspaceTrustKeys(onScreen: "Current session\n25% used"))
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
