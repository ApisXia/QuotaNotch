// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if os(macOS)
import Darwin
#endif

/// The small command surface used by the Claude Code file-based keychain.
/// Keeping this behind a protocol makes credential tests independent of the
/// user's login keychain and keeps the production path free of shell parsing.
protocol ClaudeSecurityCommandRunner: Sendable {
    func run(arguments: [String]) throws -> ClaudeSecurityCommandResult
}

struct ClaudeSecurityCommandResult: Sendable, Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

enum ClaudeSecurityCommandError: Error, Sendable, Equatable {
    case launchFailed
    case timedOut
    case outputLimitExceeded
}

/// Runs `/usr/bin/security` without a shell. Both pipes are drained while the
/// child runs, and retained output is bounded so a broken helper cannot grow
/// this process without limit. Error details are deliberately not carried into
/// the credential layer because stderr can contain account or keychain data.
struct SystemClaudeSecurityCommandRunner: ClaudeSecurityCommandRunner, Sendable {
    var executableURL = URL(fileURLWithPath: "/usr/bin/security")
    var timeout: TimeInterval = 8
    var outputLimit = 128 * 1024

    func run(arguments: [String]) throws -> ClaudeSecurityCommandResult {
        #if os(macOS)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.qualityOfService = .utility

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ClaudeSecurityCommandError.launchFailed
        }

        let stdoutCollector = LimitedClaudeCommandOutput(limit: outputLimit)
        let stderrCollector = LimitedClaudeCommandOutput(limit: outputLimit)
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdoutFD = stdoutHandle.fileDescriptor
        let stderrFD = stderrHandle.fileDescriptor
        _ = fcntl(stdoutFD, F_SETFL, fcntl(stdoutFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(stderrFD, F_SETFL, fcntl(stderrFD, F_GETFL) | O_NONBLOCK)

        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeout)
        var stdoutOpen = true
        var stderrOpen = true
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            drain(stdoutFD, isOpen: &stdoutOpen, collector: stdoutCollector)
            drain(stderrFD, isOpen: &stderrOpen, collector: stderrCollector)
            var descriptors = [pollfd]()
            if stdoutOpen { descriptors.append(pollfd(fd: stdoutFD, events: Int16(POLLIN | POLLHUP), revents: 0)) }
            if stderrOpen { descriptors.append(pollfd(fd: stderrFD, events: Int16(POLLIN | POLLHUP), revents: 0)) }
            let remaining = max(0.001, deadline - ProcessInfo.processInfo.systemUptime)
            let waitMilliseconds = Int32(min(100, max(1, Int(remaining * 1_000))))
            if descriptors.isEmpty {
                usleep(useconds_t(waitMilliseconds * 1_000))
            } else {
                _ = poll(&descriptors, nfds_t(descriptors.count), waitMilliseconds)
            }
        }

        if process.isRunning {
            process.terminate()
            let graceDeadline = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < graceDeadline {
                drain(stdoutFD, isOpen: &stdoutOpen, collector: stdoutCollector)
                drain(stderrFD, isOpen: &stderrOpen, collector: stderrCollector)
                usleep(10_000)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? stdoutHandle.close()
            try? stderrHandle.close()
            throw ClaudeSecurityCommandError.timedOut
        }

        // Reap the already-finished child, then make one final nonblocking
        // pass. If a grandchild inherited the pipes, closing our descriptors
        // here intentionally bounds the command instead of waiting forever.
        process.waitUntilExit()
        drain(stdoutFD, isOpen: &stdoutOpen, collector: stdoutCollector)
        drain(stderrFD, isOpen: &stderrOpen, collector: stderrCollector)
        try? stdoutHandle.close()
        try? stderrHandle.close()

        if stdoutCollector.exceededLimit || stderrCollector.exceededLimit {
            throw ClaudeSecurityCommandError.outputLimitExceeded
        }
        return ClaudeSecurityCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: stdoutCollector.data,
            standardError: stderrCollector.data
        )
        #else
        throw ClaudeSecurityCommandError.launchFailed
        #endif
    }

    #if os(macOS)
    private func drain(_ descriptor: Int32, isOpen: inout Bool,
                       collector: LimitedClaudeCommandOutput) {
        guard isOpen else { return }
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        for _ in 0..<4 {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                collector.append(Data(buffer.prefix(Int(count))))
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) { isOpen = false }
            return
        }
    }
    #endif
}

#if os(macOS)
private final class LimitedClaudeCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()
    private var didExceedLimit = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - storage.count)
        if chunk.count > remaining { didExceedLimit = true }
        if remaining > 0 { storage.append(contentsOf: chunk.prefix(remaining)) }
    }

    var exceededLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didExceedLimit
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
#endif

protocol ClaudeKeychainIO: Sendable {
    func read(service: String) throws -> Data
    func replace(service: String, expected: Data, updated: Data) throws -> Data
}

/// File-based Claude Code keychain adapter. It intentionally does not add
/// `-T`, `-A`, partition-list, or access-group arguments: those are owned by
/// Claude Code, and changing them would broaden trust beyond this reader.
struct SystemClaudeKeychainIO: ClaudeKeychainIO, Sendable {
    var runner: any ClaudeSecurityCommandRunner
    var account: String

    init(runner: any ClaudeSecurityCommandRunner = SystemClaudeSecurityCommandRunner(),
         account: String = NSUserName()) {
        self.runner = runner
        self.account = account
    }

    func read(service: String) throws -> Data {
        let result = try run(arguments: [
            "find-generic-password", "-s", service, "-a", account, "-w"
        ])
        guard result.terminationStatus == 0 else {
            throw result.terminationStatus == Self.itemNotFoundExitStatus
                ? QuotaFailure.notSignedIn : QuotaFailure.credentialsUnavailable
        }
        guard let data = Self.decodePassword(result.standardOutput),
              Self.isCredentialPayload(data) else {
            throw QuotaFailure.credentialsUnavailable
        }
        return data
    }

    func replace(service: String, expected: Data, updated: Data) throws -> Data {
        let current = try read(service: service)
        guard current == expected else { return current }
        guard let payload = Self.compactJSON(updated) else {
            throw QuotaFailure.credentialsUnavailable
        }
        let result = try run(arguments: [
            "add-generic-password", "-U", "-s", service, "-a", account, "-w", payload
        ])
        guard result.terminationStatus == 0 else {
            throw QuotaFailure.credentialsUnavailable
        }
        return try read(service: service)
    }

    private func run(arguments: [String]) throws -> ClaudeSecurityCommandResult {
        guard !account.isEmpty, !account.contains("\n"), !account.contains("\r") else {
            throw QuotaFailure.credentialsUnavailable
        }
        do {
            return try runner.run(arguments: arguments)
        } catch {
            // Do not expose process paths, stderr, or command arguments in a
            // user-facing credential error; they may contain sensitive data.
            throw QuotaFailure.credentialsUnavailable
        }
    }

    private static let itemNotFoundExitStatus: Int32 = 44 // -25300 modulo 256

    static func compactJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let compact = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: compact, encoding: .utf8),
              !string.contains("\n"), !string.contains("\r") else { return nil }
        return string
    }

    static func decodePassword(_ data: Data) -> Data? {
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let bytes = Array(raw.utf8)
        guard bytes.count.isMultiple(of: 2), bytes.allSatisfy({
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
        }) else {
            return Data(raw.utf8)
        }
        var decoded = Data()
        decoded.reserveCapacity(bytes.count / 2)
        var index = 0
        while index < bytes.count {
            let high = Self.hexValue(bytes[index])
            let low = Self.hexValue(bytes[index + 1])
            guard let high, let low else { return Data(raw.utf8) }
            decoded.append((high << 4) | low)
            index += 2
        }
        return decoded
    }

    private static func isCredentialPayload(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty,
              !accessToken.contains("\n"), !accessToken.contains("\r") else { return false }
        return true
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }
}
