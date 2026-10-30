// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct QuotaHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let retryAfter: String?
}

protocol QuotaTransport: Sendable {
    func send(_ request: URLRequest) async throws -> QuotaHTTPResponse
}

private final class NoQuotaRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct QuotaURLTransport: QuotaTransport {
    func send(_ request: URLRequest) async throws -> QuotaHTTPResponse {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: NoQuotaRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QuotaFailure.invalidResponse }
        return QuotaHTTPResponse(data: data, status: http.statusCode,
                                 retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}

/// When and how to ask Claude Code's /usage screen for a reading.
struct ClaudeProbe: Sendable {
    let fallback: any ClaudeQuotaFallback
    /// Given the newest reading so far (status line or an earlier /usage), whether to ask.
    let needed: @Sendable (QuotaSnapshot?) -> Bool
}

enum ClaudeProbeOutcome: Sendable {
    case none, failed
    case read(QuotaSnapshot)
}

actor QuotaClient {
    private let credentials: any QuotaCredentialSource
    private let transport: any QuotaTransport
    private let clock: @Sendable () -> Date
    private let claudeUsage: any ClaudeUsageSource
    private let claudeFallback: (any ClaudeQuotaFallback)?
    private let claudeConnected: @Sendable () -> Bool
    private var results: [QuotaProvider: QuotaResult] = [:]
    private var failures: [QuotaProvider: Int] = [:]
    /// The last reading from Claude Code's /usage screen, kept until the status line has newer numbers.
    private var claudeFallbackReading: QuotaSnapshot?
    /// When /usage last ran, and whether it failed (then it waits longer before trying again).
    private var lastProbe = Date.distantPast
    private var lastProbeFailed = false
    private var inFlight: [QuotaProvider: Task<(QuotaResult, ClaudeProbeOutcome), Never>] = [:]

    /// The status line only reports while Claude Code runs in a terminal, so Claude used
    /// elsewhere (the VS Code extension) or not at all leaves it silent. Then QuotaNotch asks
    /// /usage itself: after Claude activity newer than the last reading, at most every
    /// `probeSpacing`, and otherwise when the reading is older than `idleProbeAge`.
    static let probeSpacing: TimeInterval = 180
    static let idleProbeAge: TimeInterval = 1800
    /// After a failed /usage run (for example no network), wait this long before the next.
    static let failedProbeSpacing: TimeInterval = 600

    init(credentials: any QuotaCredentialSource = LocalQuotaCredentials(),
         transport: any QuotaTransport = QuotaURLTransport(),
         clock: @escaping @Sendable () -> Date = { Date() },
         claudeUsage: any ClaudeUsageSource = ClaudeStatusLineUsage(directory: ClaudeStatusLineUsage.defaultDirectory),
         claudeFallback: (any ClaudeQuotaFallback)? = nil,
         claudeConnected: @escaping @Sendable () -> Bool = {
             FileManager.default.fileExists(atPath: ClaudeStatusLineUsage.defaultDirectory.path)
         }) {
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.claudeUsage = claudeUsage
        self.claudeFallback = claudeFallback
        self.claudeConnected = claudeConnected
    }

    /// All callers, including manual refresh and multiple displays, share the same cooldown.
    /// `manual` lets a user-initiated Claude refresh run /usage when the status line has nothing
    /// in the last 10 minutes. Scheduled refreshes run it only while Claude is connected, as
    /// described at `probeSpacing`; `claudeActivity` is when a Claude session last changed.
    func refresh(_ provider: QuotaProvider, manual: Bool = false, claudeActivity: Date? = nil) async -> QuotaResult {
        if let task = inFlight[provider] { return await task.value.0 }
        let now = clock()
        if let result = results[provider], result.nextAttempt > now,
           !Self.mayBypassCooldown(provider: provider, manual: manual, result: result, now: now) { return result }
        let old = results[provider]?.snapshot
        let attempt = failures[provider, default: 0] + 1
        let credentials = self.credentials
        let transport = self.transport
        let claudeUsage = self.claudeUsage
        var probe: ClaudeProbe?
        if provider == .claude, let fallback = claudeFallback {
            if manual {
                probe = ClaudeProbe(fallback: fallback) { reading in
                    reading.map { now.timeIntervalSince($0.fetchedAt) > 600 } ?? true
                }
            } else if claudeConnected(),
                      now.timeIntervalSince(lastProbe) >= (lastProbeFailed ? Self.failedProbeSpacing : Self.probeSpacing) {
                let idle = Self.idleProbeAge
                probe = ClaudeProbe(fallback: fallback) { reading in
                    guard let reading else { return true }
                    if let claudeActivity, claudeActivity > reading.fetchedAt { return true }
                    return now.timeIntervalSince(reading.fetchedAt) > idle
                }
            }
        }
        let previousFallback = claudeFallbackReading
        let clock = self.clock
        let task = Task<(QuotaResult, ClaudeProbeOutcome), Never> {
            var outcome = ClaudeProbeOutcome.none
            do {
                try Task.checkCancellation()
                let snapshot: QuotaSnapshot
                if provider == .claude {
                    let reading = await Self.claudeSnapshot(usage: claudeUsage, probe: probe,
                                                            previousFallback: previousFallback, now: now)
                    outcome = reading.probe
                    snapshot = try reading.result.get()
                } else {
                    snapshot = try await Self.codexSnapshot(credentials: credentials, transport: transport, now: now)
                }
                return (QuotaResult(snapshot: snapshot, failure: nil,
                                    nextAttempt: clock().addingTimeInterval(provider.interval)), outcome)
            } catch {
                // Never surface server bodies, headers, URLs with credentials, or raw errors.
                let failure = error as? QuotaFailure ?? .network
                return (QuotaResult(snapshot: failure.clearsSnapshot ? nil : old, failure: failure,
                                    nextAttempt: Self.nextAttempt(after: failure, provider: provider,
                                                                  attempt: attempt, now: clock())), outcome)
            }
        }
        inFlight[provider] = task
        let (result, outcome) = await task.value
        inFlight[provider] = nil
        results[provider] = result
        failures[provider] = result.failure == nil ? 0 : attempt
        switch outcome {
        case .none: break
        case .failed: lastProbe = now; lastProbeFailed = true
        case .read(let snapshot):
            lastProbe = now; lastProbeFailed = false
            if snapshot.fetchedAt > (claudeFallbackReading?.fetchedAt ?? .distantPast) { claudeFallbackReading = snapshot }
        }
        return result
    }

    /// A manual Claude refresh may run early when there is nothing recent to show,
    /// but never against a server cooldown.
    static func mayBypassCooldown(provider: QuotaProvider, manual: Bool, result: QuotaResult, now: Date) -> Bool {
        guard manual, provider == .claude else { return false }
        if case .rateLimited? = result.failure { return false }
        guard let snapshot = result.snapshot else { return true }
        return now.timeIntervalSince(snapshot.fetchedAt) > 600
    }

    private static func claudeSnapshot(usage: any ClaudeUsageSource, probe: ClaudeProbe?,
                                       previousFallback: QuotaSnapshot?, now: Date)
        async -> (result: Result<QuotaSnapshot, QuotaFailure>, probe: ClaudeProbeOutcome) {
        var reported: QuotaSnapshot?
        do { reported = try await usage.latest(now: now) }
        catch QuotaFailure.notConnected { reported = nil }
        catch { return (.failure(error as? QuotaFailure ?? .network), .none) }
        let statusLine = reported
        // An earlier /usage reading stays until the status line reports something newer.
        if let previousFallback, previousFallback.fetchedAt > (reported?.fetchedAt ?? .distantPast) {
            reported = previousFallback
        } else if let previousFallback, let newer = reported {
            // The status line has no per-model weeks; keep those /usage reported until it runs again.
            let extra = previousFallback.windows.filter { window in !newer.windows.contains { $0.id == window.id } }
            if !extra.isEmpty { reported = QuotaSnapshot(windows: newer.windows + extra, fetchedAt: newer.fetchedAt) }
        }
        // Ask Claude Code's /usage screen when the status line is silent or behind.
        if let probe, probe.needed(reported) {
            do {
                var reading = try await probe.fallback.fetch(now: now)
                // A reset the screen didn't show is taken from the previous reading while it is still ahead.
                let earlierReadings = [reported, statusLine].compactMap { $0 }
                if !earlierReadings.isEmpty {
                    reading = QuotaSnapshot(windows: reading.windows.map { window in
                        guard window.resetsAt == nil,
                              let earlier = earlierReadings.lazy.compactMap({ snapshot in
                                  snapshot.windows.first(where: { $0.id == window.id })?.resetsAt
                              }).first(where: { $0 > now }) else { return window }
                        var filled = QuotaWindow(id: window.id, title: window.title,
                                                 remainingPercent: window.remainingPercent, resetsAt: earlier)
                        filled.duration = window.duration
                        return filled
                    }, fetchedAt: reading.fetchedAt)
                }
                return (.success(reading), .read(reading))
            } catch QuotaFailure.rateLimited(let date) {
                return (.failure(.rateLimited(date)), .failed)
            } catch {
                guard let reported else { return (.failure(.notConnected), .failed) }
                return (.success(reported), .failed)
            }
        }
        guard let reported else { return (.failure(.notConnected), .none) }
        return (.success(reported), .none)
    }

    private static func codexSnapshot(credentials: any QuotaCredentialSource, transport: any QuotaTransport,
                                      now: Date) async throws -> QuotaSnapshot {
        let credential = try await credentials.load(.codex)
        if let expiry = credential.expiresAt, expiry <= now { throw QuotaFailure.expired }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaNotch", forHTTPHeaderField: "User-Agent")
        if let accountID = credential.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        try Task.checkCancellation()
        let response = try await transport.send(request)
        switch response.status {
        case 200: break
        // Only 401 means the login itself was rejected; a 403 can come from an edge proxy.
        case 401: throw QuotaFailure.expired
        case 429: throw QuotaFailure.rateLimited(retryDate(response.retryAfter, now: now))
        default: throw QuotaFailure.http(response.status)
        }
        return try QuotaParser.parse(response.data, provider: .codex, now: now)
    }

    /// Local readings are retried at the normal pace; a rejected login waits for the user;
    /// server and network errors back off exponentially (1, 2, 4 … 30 minutes).
    static func nextAttempt(after failure: QuotaFailure, provider: QuotaProvider, attempt: Int, now: Date) -> Date {
        switch failure {
        case .rateLimited(let date): return max(date, now.addingTimeInterval(60))
        case .notConnected: return now.addingTimeInterval(provider.interval)
        case .notSignedIn, .credentialsUnavailable: return now.addingTimeInterval(60)
        case .expired: return now.addingTimeInterval(900)
        case .network, .invalidResponse, .http:
            let exponent = min(max(attempt - 1, 0), 5)
            return now.addingTimeInterval(min(1800, 60 * pow(2, Double(exponent))))
        }
    }

    static func retryDate(_ raw: String?, now: Date) -> Date {
        if let raw, let seconds = Double(raw), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(max(60, seconds))
        }
        if let raw {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: raw), date > now {
                return max(date, now.addingTimeInterval(60))
            }
        }
        return now.addingTimeInterval(900)
    }
}
