// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

protocol GeminiQuotaSource: Sendable {
    func fetch(now: Date) async throws -> QuotaSnapshot
}

/// Gemini quota for Google Antigravity accounts, read the way CodexBar does: the `agy` CLI
/// prints its own /usage report as JSON (`agy -p /usage --output-format json`). No prompt is
/// sent to a model, and no token, Keychain item or credentials file is read by QuotaNotch.
struct AntigravityCLIQuota: GeminiQuotaSource {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var timeout: TimeInterval = 60

    /// Older versions have no usage report and could treat "/usage" as a prompt to a model.
    static let minimumVersion = [1, 1, 11]

    func fetch(now: Date) async throws -> QuotaSnapshot {
        #if os(macOS)
        let running = AntigravityCLIRun()
        let result: Result<QuotaSnapshot, Error> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Result { try report(now: now, running: running) })
                }
            }
        } onCancel: { running.cancel() }
        return try result.get()
        #else
        // Linux CI/tests never start a CLI found in their environment.
        throw QuotaFailure.notSignedIn
        #endif
    }

    /// The `agy` executable: `ANTIGRAVITY_CLI_PATH` when set (and nothing else then), otherwise
    /// the first one on PATH or in the usual install folders.
    static func binary(environment: [String: String], home: URL) -> URL? {
        let files = FileManager.default
        if let configured = environment["ANTIGRAVITY_CLI_PATH"] {
            return configured.hasPrefix("/") && files.isExecutableFile(atPath: configured)
                ? URL(fileURLWithPath: configured) : nil
        }
        return searchPath(environment: environment, home: home)
            .map { URL(fileURLWithPath: $0).appendingPathComponent("agy") }
            .first { files.isExecutableFile(atPath: $0.path) }
    }

    static func searchPath(environment: [String: String], home: URL) -> [String] {
        ((environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .filter { $0.hasPrefix("/") }
    }

    /// `agy --version` prints a plain "1.2.11"; anything else is unknown.
    static func version(_ output: String) -> [Int]? {
        let fields = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Int($0) }
        guard fields.count == 3, parts.count == 3, parts.allSatisfy({ $0 >= 0 }) else { return nil }
        return parts
    }

    static func supports(_ version: [Int]) -> Bool { !version.lexicographicallyPrecedes(minimumVersion) }

    #if os(macOS)
    private func report(now: Date, running: AntigravityCLIRun) throws -> QuotaSnapshot {
        guard let binary = Self.binary(environment: environment, home: home) else { throw QuotaFailure.notSignedIn }
        // An empty private folder: agy works there, and it holds the stand-in browser launchers.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotanotch-agy-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        var env = environment
        env["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true" // agy ignores "1".
        // When its login has lapsed agy would open the browser to sign in, even in print mode.
        // A background reading must not: these stand-ins fail, and the reading fails with them.
        for command in ["open", "xdg-open"] {
            guard FileManager.default.createFile(atPath: directory.appendingPathComponent(command).path,
                                                 contents: Data("#!/bin/sh\nexit 1\n".utf8),
                                                 attributes: [.posixPermissions: 0o700]) else { throw QuotaFailure.invalidResponse }
        }
        env["PATH"] = ([directory.path] + Self.searchPath(environment: environment, home: home)).joined(separator: ":")
        env["BROWSER"] = directory.appendingPathComponent("open").path

        let versionOutput = try run(binary, ["--version"], env: env, directory: directory, limit: 5, running: running)
        guard let version = Self.version(String(decoding: versionOutput, as: UTF8.self)), Self.supports(version) else {
            throw QuotaFailure.invalidResponse
        }
        let output = try run(binary, ["-p", "/usage", "--output-format", "json", "--print-timeout", "\(Int(timeout))s"],
                             env: env, directory: directory, limit: timeout, running: running)
        return try QuotaParser.parse(output, provider: .gemini, now: now)
    }

    /// Runs to the end and returns what was printed (at most 1 MB). A run that fails, or is
    /// stopped at the time limit, is reported as a failed reading; its output is never shown.
    private func run(_ binary: URL, _ arguments: [String], env: [String: String], directory: URL,
                     limit: TimeInterval, running: AntigravityCLIRun) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = env
        process.currentDirectoryURL = directory
        process.qualityOfService = .utility
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let output = AntigravityCLIOutput()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; output.finish() } else { output.append(chunk) }
        }
        defer { pipe.fileHandleForReading.readabilityHandler = nil }
        do { try process.run() } catch { throw QuotaFailure.notSignedIn }
        let deadline = ProcessInfo.processInfo.systemUptime + limit
        while process.isRunning {
            if running.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline || output.count > 1_048_576 {
                process.terminate()
                let end = ProcessInfo.processInfo.systemUptime + 1
                while process.isRunning && ProcessInfo.processInfo.systemUptime < end { usleep(20_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                if running.isCancelled { throw CancellationError() }
                throw output.count > 1_048_576 ? QuotaFailure.invalidResponse : QuotaFailure.network
            }
            usleep(50_000)
        }
        process.waitUntilExit()
        // The pipe may still hold the last lines after the process has gone.
        let end = ProcessInfo.processInfo.systemUptime + 1
        while !output.finished && ProcessInfo.processInfo.systemUptime < end { usleep(10_000) }
        guard process.terminationStatus == 0 else { throw QuotaFailure.invalidResponse }
        return output.data
    }
    #endif
}

#if os(macOS)
/// What a run has printed so far, appended from the pipe's reading queue.
private final class AntigravityCLIOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var ended = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return buffer.count }
    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
    func append(_ chunk: Data) { lock.lock(); defer { lock.unlock() }; buffer.append(chunk) }
    /// Set once the reading handler has seen the end of the output.
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return ended }
    func finish() { lock.lock(); defer { lock.unlock() }; ended = true }
}

private final class AntigravityCLIRun: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
}
#endif
