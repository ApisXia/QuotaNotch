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
    private let claudeFallback: (any ClaudeQuotaFallback)?
    private var results: [QuotaProvider: QuotaResult] = [:]
    private var inFlight: [QuotaProvider: Task<QuotaResult, Never>] = [:]

    init(credentials: any QuotaCredentialSource = LocalQuotaCredentials(),
         transport: any QuotaTransport = QuotaURLTransport(),
         clock: @escaping @Sendable () -> Date = { Date() },
         claudeFallback: (any ClaudeQuotaFallback)? = nil) {
        self.credentials = credentials
        self.transport = transport
        self.clock = clock
        self.claudeFallback = claudeFallback
    }

    /// All callers, including manual refresh and multiple displays, share the same cooldown.
    func refresh(_ provider: QuotaProvider) async -> QuotaResult {
        if let task = inFlight[provider] { return await task.value }
        let now = clock()
        if let result = results[provider], result.nextAttempt > now { return result }
        let old = results[provider]?.snapshot
        let credentials = self.credentials
        let transport = self.transport
        let claudeFallback = self.claudeFallback
        let clock = self.clock
        let task = Task<QuotaResult, Never> {
            do {
                try Task.checkCancellation()
                if provider == .claude {
                    let snapshot = try await ClaudeQuotaProbe(credentials: credentials, transport: transport,
                        fallback: claudeFallback, clock: clock).fetch()
                    return QuotaResult(snapshot: snapshot, failure: nil,
                        nextAttempt: clock().addingTimeInterval(provider.interval))
                }
                let credential = try await credentials.load(provider)
                if let expiry = credential.expiresAt, expiry <= now { throw QuotaFailure.expired }
                if provider == .gemini {
                    let snapshot = try await Self.geminiSnapshot(credential, transport: transport, now: now)
                    return QuotaResult(snapshot: snapshot, failure: nil, nextAttempt: now.addingTimeInterval(provider.interval))
                }
                let endpoint = "https://chatgpt.com/backend-api/wham/usage"
                var request = URLRequest(url: URL(string: endpoint)!)
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
                case 401, 403: throw QuotaFailure.expired
                case 429: throw QuotaFailure.rateLimited(Self.retryDate(response.retryAfter, now: now))
                default: throw QuotaFailure.http(response.status)
                }
                let snapshot = try QuotaParser.parse(response.data, provider: provider, now: now)
                return QuotaResult(snapshot: snapshot, failure: nil, nextAttempt: now.addingTimeInterval(provider.interval))
            } catch {
                // Never surface server bodies, headers, URLs with credentials, or raw errors.
                let failure = error as? QuotaFailure ?? .network
                let retry: Date
                if case .rateLimited(let date) = failure { retry = date }
                else { retry = now.addingTimeInterval(60) }
                let clear: Bool
                switch failure {
                case .notSignedIn, .expired, .credentialsUnavailable: clear = true
                default: clear = false
                }
                return QuotaResult(snapshot: clear ? nil : old, failure: failure, nextAttempt: retry)
            }
        }
        inFlight[provider] = task
        let result = await task.value
        inFlight[provider] = nil
        results[provider] = result
        return result
    }

    private static func geminiSnapshot(_ credential: QuotaCredential, transport: any QuotaTransport, now: Date) async throws -> QuotaSnapshot {
        func post(_ method: String, body: [String: Any]) async throws -> Data {
            var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:" + method)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            try Task.checkCancellation()
            let response = try await transport.send(request)
            switch response.status {
            case 200: return response.data
            case 401, 403: throw QuotaFailure.expired
            case 429: throw QuotaFailure.rateLimited(retryDate(response.retryAfter, now: now))
            default: throw QuotaFailure.http(response.status)
            }
        }
        let bootstrap = try await post("loadCodeAssist", body: ["metadata": ["pluginType": "GEMINI"]])
        guard let root = try? JSONSerialization.jsonObject(with: bootstrap) as? [String: Any],
              let project = root["cloudaicompanionProject"] as? String, !project.isEmpty else {
            throw QuotaFailure.invalidResponse
        }
        let data = try await post("retrieveUserQuota", body: ["project": project])
        return try QuotaParser.parse(data, provider: .gemini, now: now)
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
