import XCTest
@testable import QuotaNotchCore

private let now = Date(timeIntervalSince1970: 1_789_400_000)

final class ClaudeStatusLineUsageTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("statusline-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func record(_ name: String, observed: TimeInterval, fiveHour: Double, resets: TimeInterval = 1_789_401_600) throws {
        let body = #"{"observed_at":\#(observed),"rate_limits":{"five_hour":{"used_percentage":\#(fiveHour),"resets_at":\#(resets)},"seven_day":{"used_percentage":10,"resets_at":1789826400}}}"#
        try Data(body.utf8).write(to: directory.appendingPathComponent(name + ".json"))
    }

    func testNewestChangedSessionWins() async throws {
        try record("idle-terminal", observed: now.timeIntervalSince1970 - 3600, fiveHour: 40)
        try record("busy-terminal", observed: now.timeIntervalSince1970 - 60, fiveHour: 55)
        let snapshot = try await ClaudeStatusLineUsage(directory: directory).latest(now: now)
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [45, 90])
        XCTAssertEqual(snapshot.fetchedAt, now.addingTimeInterval(-60))
    }

    func testMissingDirectoryOrNoRecordsIsNotConnected() async throws {
        let missing = ClaudeStatusLineUsage(directory: directory.appendingPathComponent("absent"))
        await assertNotConnected(missing)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("bad.json"))
        await assertNotConnected(ClaudeStatusLineUsage(directory: directory))
    }

    func testOldRecordsArePruned() async throws {
        try record("ancient", observed: now.timeIntervalSince1970 - 9 * 24 * 3600, fiveHour: 10)
        await assertNotConnected(ClaudeStatusLineUsage(directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ancient.json").path))
    }

    private func assertNotConnected(_ source: ClaudeStatusLineUsage, line: UInt = #line) async {
        do { _ = try await source.latest(now: now); XCTFail("expected notConnected", line: line) }
        catch { XCTAssertEqual(error as? QuotaFailure, .notConnected, line: line) }
    }
}

final class ClaudeStatusLineConfigurationTests: XCTestCase {
    private let helper = "/Users/me/Library/Application Support/QuotaNotch/Activity/QuotaNotchMonitorHook"
    private let usage = "/Users/me/Library/Application Support/QuotaNotch/ClaudeStatusLine"

    func testInstallWithoutExistingStatusLineAndRemoveRestoresFile() throws {
        let original = Data("{\n  \"model\": \"opus\"\n}\n".utf8)
        let installed = try ClaudeStatusLineConfiguration.installing(original, helper: helper, usageDirectory: usage)
        XCTAssertTrue(ClaudeStatusLineConfiguration.isInstalled(installed))
        let command = try XCTUnwrap(OrderedJSON.parse(installed)["statusLine"]?["command"]?.stringValue)
        XCTAssertEqual(ShellWords.split(command), [helper, "statusline", usage])
        XCTAssertEqual(try ClaudeStatusLineConfiguration.removing(installed), original)
    }

    func testChainsExistingCommandAndKeepsOtherFields() throws {
        let original = Data("""
        {
          "statusLine": {
            "type": "command",
            "command": "bash -c 'echo \\"$(whoami)\\"' | tr a-z A-Z",
            "padding": 0
          }
        }

        """.utf8)
        let installed = try ClaudeStatusLineConfiguration.installing(original, helper: helper, usageDirectory: usage)
        let line = try OrderedJSON.parse(installed)["statusLine"]
        XCTAssertEqual(line?["padding"], .number("0"))
        let parsed = try XCTUnwrap(ClaudeStatusLineConfiguration.parse(line?["command"]?.stringValue ?? ""))
        XCTAssertEqual(parsed.chained, "bash -c 'echo \"$(whoami)\"' | tr a-z A-Z")
        // Installing twice must not wrap QuotaNotch inside itself.
        XCTAssertEqual(try ClaudeStatusLineConfiguration.installing(installed, helper: helper, usageDirectory: usage), installed)
        XCTAssertEqual(try ClaudeStatusLineConfiguration.removing(installed), original)
    }

    func testRemovingLeavesSomeoneElsesStatusLineAlone() throws {
        let original = Data(#"{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}"#.utf8)
        XCTAssertFalse(ClaudeStatusLineConfiguration.isInstalled(original))
        XCTAssertEqual(try ClaudeStatusLineConfiguration.removing(original), original)
    }

    func testShellWordsRoundTripsQuoting() {
        for value in ["plain", "it's", "a b", "", "''", "\\", "$(x) `y` \"z\""] {
            XCTAssertEqual(ShellWords.split(AgentHookConfiguration.shellQuote(value) + " " + AgentHookConfiguration.shellQuote("next")),
                           [value, "next"], value)
        }
        XCTAssertNil(ShellWords.split("'unterminated"))
    }
}
