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

actor QuotaClient {
    private let credentials: any QuotaCredentialSource
    private let transport: any QuotaTransport
    private let clock: @Sendable () -> Date
    private let claudeUsage: any ClaudeUsageSource
    private let claudeFallback: (any ClaudeQuotaFallback)?
    private var results: [QuotaProvider: QuotaResult] = [:]
    private var failures: [QuotaProvider: Int] = [:]
    /// The last reading from Claude Code's /usage screen, kept until the status line has newer numbers.
    private var claudeFallbackReading: QuotaSnapshot?
    private var inFlight: [QuotaProvider: Task<QuotaResult, Never>] = [:]

    init(credentials: any QuotaCredentialSource = LocalQuotaCredentials(),
         transport: any QuotaTransport = QuotaURLTransport(),
         clock: @escaping @Sendable () -> Date = { Date() },
         claudeUsage: any ClaudeUsageSource = ClaudeStatusLineUsage(directory: ClaudeStatusLineUsage.defaultDirectory),
         claudeFallback: (any ClaudeQuotaFallback)? = nil) {
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.claudeUsage = claudeUsage
        self.claudeFallback = claudeFallback
    }

    /// All callers, including manual refresh and multiple displays, share the same cooldown.
    /// `manual` lets a user-initiated Claude refresh run the slow CLI fallback when the status
    /// line has nothing recent; scheduled refreshes never start a process.
    func refresh(_ provider: QuotaProvider, manual: Bool = false) async -> QuotaResult {
        if let task = inFlight[provider] { return await task.value }
        let now = clock()
        if let result = results[provider], result.nextAttempt > now,
           !Self.mayBypassCooldown(provider: provider, manual: manual, result: result, now: now) { return result }
        let old = results[provider]?.snapshot
        let attempt = failures[provider, default: 0] + 1
        let credentials = self.credentials
        let transport = self.transport
        let claudeUsage = self.claudeUsage
        let claudeFallback = manual ? self.claudeFallback : nil
        let previousFallback = claudeFallbackReading
        let clock = self.clock
        let task = Task<QuotaResult, Never> {
            do {
                try Task.checkCancellation()
                let snapshot: QuotaSnapshot
                if provider == .claude {
                    snapshot = try await Self.claudeSnapshot(usage: claudeUsage, fallback: claudeFallback,
                                                             previousFallback: previousFallback, now: now)
                } else {
                    snapshot = try await Self.codexSnapshot(credentials: credentials, transport: transport, now: now)
                }
                return QuotaResult(snapshot: snapshot, failure: nil,
                                   nextAttempt: clock().addingTimeInterval(provider.interval))
            } catch {
                // Never surface server bodies, headers, URLs with credentials, or raw errors.
                let failure = error as? QuotaFailure ?? .network
                return QuotaResult(snapshot: failure.clearsSnapshot ? nil : old, failure: failure,
                                   nextAttempt: Self.nextAttempt(after: failure, provider: provider,
                                                                 attempt: attempt, now: clock()))
            }
        }
        inFlight[provider] = task
        let result = await task.value
        inFlight[provider] = nil
        results[provider] = result
        failures[provider] = result.failure == nil ? 0 : attempt
        if provider == .claude, let snapshot = result.snapshot,
           snapshot.fetchedAt > (claudeFallbackReading?.fetchedAt ?? .distantPast), manual {
            claudeFallbackReading = snapshot
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

    private static func claudeSnapshot(usage: any ClaudeUsageSource, fallback: (any ClaudeQuotaFallback)?,
                                       previousFallback: QuotaSnapshot?, now: Date) async throws -> QuotaSnapshot {
        var reported: QuotaSnapshot?
        do { reported = try await usage.latest(now: now) }
        catch QuotaFailure.notConnected { reported = nil }
        // An earlier /usage reading stays until the status line reports something newer.
        if let previousFallback, previousFallback.fetchedAt > (reported?.fetchedAt ?? .distantPast) {
            reported = previousFallback
        }
        // A manual refresh may ask Claude Code's /usage screen when the status line is silent or old.
        if let fallback, reported.map({ now.timeIntervalSince($0.fetchedAt) > 600 }) ?? true {
            do { return try await fallback.fetch(now: now) }
            catch QuotaFailure.rateLimited(let date) { throw QuotaFailure.rateLimited(date) }
            catch {}
        }
        guard let reported else { throw QuotaFailure.notConnected }
        return reported
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
