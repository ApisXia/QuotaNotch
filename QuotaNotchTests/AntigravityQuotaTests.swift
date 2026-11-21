import XCTest
@testable import QuotaNotchCore

private let fixtureNow = Date(timeIntervalSince1970: 1_789_400_000)

private struct FixtureGemini: GeminiQuotaSource {
    let result: Result<QuotaSnapshot, QuotaFailure>
    func fetch(now: Date) async throws -> QuotaSnapshot { try result.get() }
}

final class AntigravityQuotaTests: XCTestCase {
    private func report(_ groups: String, status: String = "SUCCESS", command: String = "usage") -> Data {
        Data(#"{"status":"\#(status)","command":{"name":"\#(command)","data":{"groups":\#(groups)}}}"#.utf8)
    }

    func testUsageReportGeminiFirstShortestWindowFirst() throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "gemini", withExtension: "json")))
        let result = try QuotaParser.parse(data, provider: .gemini, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.id), ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"])
        XCTAssertEqual(result.windows.map(\.title), ["5 小时", "7 天", "Claude and GPT · 5 小时", "Claude and GPT · 7 天"])
        XCTAssertEqual(result.windows.map { ($0.remainingPercent * 100).rounded() / 100 }, [95, 86, 100, 89])
        XCTAssertEqual(result.windows[1].resetsAt, QuotaParser.isoDate("2026-09-17T18:40:27Z"))
        let periods: [TimeInterval?] = [5 * 3600, 7 * 86400, 5 * 3600, 7 * 86400]
        XCTAssertEqual(result.windows.map(\.period), periods)
        XCTAssertEqual(result.fetchedAt, fixtureNow)
    }

    func testWeeklyOnlyAccountAndModelGroupKeepTheirNames() throws {
        let groups = #"""
        [{"name":"Gemini Models","buckets":[{"id":"gemini-weekly","remaining_fraction":0.4}]},
         {"name":"Gemini 4 Argon","buckets":[{"id":"gemini-4-argon-weekly","window":"weekly","remaining_fraction":1}]}]
        """#
        let result = try QuotaParser.parse(report(groups), provider: .gemini, now: fixtureNow)
        XCTAssertEqual(result.windows.map(\.title), ["7 天", "Gemini 4 Argon · 7 天"])
        XCTAssertEqual(result.windows.map(\.remainingPercent), [40, 100])
        XCTAssertNil(result.windows[0].resetsAt)
    }

    func testUnknownDisabledAndFailedReportsAreNotReadAsQuota() {
        let unknown = #"[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","reset_time":"2026-09-13T03:48:04Z"}]}]"#
        let disabled = #"[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","disabled":true,"remaining_fraction":1}]}]"#
        let beyond = #"[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","remaining_fraction":86}]}]"#
        let good = #"[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","remaining_fraction":0.5}]}]"#
        for data in [report(unknown), report(disabled), report(beyond), report("[]"),
                     report(good, status: "ERROR"), report(good, command: "help"), Data("not json".utf8)] {
            XCTAssertThrowsError(try QuotaParser.parse(data, provider: .gemini, now: fixtureNow))
        }
        XCTAssertNoThrow(try QuotaParser.parse(report(good), provider: .gemini, now: fixtureNow))
    }

    func testVersionGate() {
        XCTAssertEqual(AntigravityCLIQuota.version("1.2.11\n"), [1, 2, 11])
        XCTAssertNil(AntigravityCLIQuota.version("agy 1.2.11"))
        XCTAssertNil(AntigravityCLIQuota.version("1.2"))
        XCTAssertFalse(AntigravityCLIQuota.supports([1, 1, 10]))
        XCTAssertTrue(AntigravityCLIQuota.supports([1, 1, 11]))
        XCTAssertTrue(AntigravityCLIQuota.supports([1, 2, 0]))
        XCTAssertTrue(AntigravityCLIQuota.supports([2, 0, 0]))
    }

    func testConfiguredCLIPathIsTheOnlyOneUsed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaNotchTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agy = directory.appendingPathComponent("agy")
        XCTAssertTrue(FileManager.default.createFile(atPath: agy.path, contents: Data("#!/bin/sh\n".utf8),
                                                     attributes: [.posixPermissions: 0o700]))
        let found = AntigravityCLIQuota.binary(environment: ["PATH": directory.path], home: directory)
        XCTAssertEqual(found?.path, agy.path)
        XCTAssertNil(AntigravityCLIQuota.binary(environment: ["PATH": directory.path, "ANTIGRAVITY_CLI_PATH": directory.path + "/missing"],
                                                home: directory))
    }

    func testClientReportsGeminiReadingsAndFailures() async throws {
        let snapshot = QuotaSnapshot(windows: [QuotaWindow(id: "gemini-5h", title: "5 小时", remainingPercent: 95, resetsAt: nil)],
                                     fetchedAt: fixtureNow)
        let good = await QuotaClient(clock: { fixtureNow }, gemini: FixtureGemini(result: .success(snapshot))).refresh(.gemini)
        XCTAssertEqual(good.snapshot, snapshot)
        XCTAssertNil(good.failure)
        XCTAssertEqual(good.nextAttempt, fixtureNow.addingTimeInterval(600))
        let missing = await QuotaClient(clock: { fixtureNow }, gemini: FixtureGemini(result: .failure(.notSignedIn))).refresh(.gemini)
        XCTAssertNil(missing.snapshot)
        XCTAssertEqual(missing.failure, .notSignedIn)
    }
}
