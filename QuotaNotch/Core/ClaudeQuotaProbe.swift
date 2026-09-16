// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol ClaudeQuotaFallback: Sendable {
    func fetch(now: Date) async throws -> QuotaSnapshot
}

struct ClaudeQuotaProbe: Sendable {
    let credentials: any QuotaCredentialSource
    let transport: any QuotaTransport
    var fallback: (any ClaudeQuotaFallback)? = nil
    var clock: @Sendable () -> Date = { Date() }

    func fetch() async throws -> QuotaSnapshot {
        do { return try await fetchAPI() }
        catch {
            let primary = error
            // A second route reaches the same rate-limited service; honor its cooldown.
            if case QuotaFailure.rateLimited = primary { throw primary }
            if primary is CancellationError || Task.isCancelled { throw CancellationError() }
            guard let fallback else { throw primary }
            do { return try await fallback.fetch(now: clock()) }
            catch let failure as QuotaFailure {
                if case .rateLimited = failure { throw failure }
                throw primary
            } catch { throw primary }
        }
    }

    private func fetchAPI() async throws -> QuotaSnapshot {
        var credential = try await credentials.load(.claude)
        var renewed = false
        if needsRefresh(credential), credential.refreshToken != nil {
            credential = try await renewOrReload(credential)
            renewed = true
        }
        if let expiry = credential.expiresAt, expiry <= clock() { throw QuotaFailure.expired }
        do { return try await usage(credential) }
        catch QuotaFailure.expired {
            // Reload first: the CLI may already have replaced the rejected token.
            let latest = try await credentials.load(.claude)
            if latest != credential {
                credential = latest
                if needsRefresh(credential), credential.refreshToken != nil, !renewed {
                    credential = try await renewOrReload(credential)
                }
            } else if !renewed, credential.refreshToken != nil {
                credential = try await renewOrReload(credential)
            } else { throw QuotaFailure.expired }
            return try await usage(credential)
        }
    }

    private func needsRefresh(_ credential: QuotaCredential) -> Bool {
        credential.expiresAt.map { $0 <= clock().addingTimeInterval(300) } ?? true
    }

    private func renewOrReload(_ original: QuotaCredential) async throws -> QuotaCredential {
        // One refresh operation per probe, shared by QuotaClient's in-flight task.
        let latest = try await credentials.load(.claude)
        if latest != original, !needsRefresh(latest) { return latest }
        do { return try await renew(latest) }
        catch {
            if case QuotaFailure.rateLimited = error { throw error }
            if let reread = try? await credentials.load(.claude), reread != latest,
               reread.expiresAt.map({ $0 > clock() }) ?? true { return reread }
            throw error
        }
    }

    private func renew(_ original: QuotaCredential) async throws -> QuotaCredential {
        guard let refreshToken = original.refreshToken else { throw QuotaFailure.expired }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Omitting scope preserves the original grant instead of adding permissions.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        ])
        try Task.checkCancellation()
        let response = try await transport.send(request)
        if response.status == 429 { throw QuotaFailure.rateLimited(QuotaClient.retryDate(response.retryAfter, now: clock())) }
        if [400, 401, 403].contains(response.status) { throw QuotaFailure.expired }
        guard (200...299).contains(response.status) else { throw QuotaFailure.http(response.status) }
        guard let root = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let token = root["access_token"] as? String, validToken(token),
              let seconds = QuotaParser.number(root["expires_in"]), seconds > 0,
              clock().timeIntervalSince1970 + seconds < Date.distantFuture.timeIntervalSince1970 else {
            throw QuotaFailure.invalidResponse
        }
        let refresh = root["refresh_token"] as? String ?? refreshToken
        guard validToken(refresh) else { throw QuotaFailure.invalidResponse }
        var updated = QuotaCredential(accessToken: token, accountID: original.accountID,
            expiresAt: clock().addingTimeInterval(seconds), refreshToken: refresh, location: original.location)
        updated = try await credentials.saveClaude(updated, replacing: original)
        return updated
    }

    private func usage(_ credential: QuotaCredential) async throws -> QuotaSnapshot {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("QuotaNotch", forHTTPHeaderField: "User-Agent")
        try Task.checkCancellation()
        let response = try await transport.send(request)
        switch response.status {
        case 200: return try QuotaParser.parse(response.data, provider: .claude, now: clock())
        case 401, 403: throw QuotaFailure.expired
        case 429: throw QuotaFailure.rateLimited(QuotaClient.retryDate(response.retryAfter, now: clock()))
        default: throw QuotaFailure.http(response.status)
        }
    }

    private func validToken(_ token: String) -> Bool {
        !token.isEmpty && !token.contains("\r") && !token.contains("\n")
    }
}
