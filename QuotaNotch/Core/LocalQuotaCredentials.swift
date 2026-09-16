// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct QuotaCredential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let accessToken: String
    let accountID: String?
    let expiresAt: Date?
    var refreshToken: String? = nil
    var location: ClaudeCredentialLocation? = nil
    var description: String { "QuotaCredential(<redacted>)" }
    var debugDescription: String { description }
}

protocol QuotaCredentialSource: Sendable {
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential
    func saveClaude(_ updated: QuotaCredential, replacing original: QuotaCredential) async throws -> QuotaCredential
}

extension QuotaCredentialSource {
    func saveClaude(_ updated: QuotaCredential, replacing original: QuotaCredential) async throws -> QuotaCredential {
        throw QuotaFailure.credentialsUnavailable
    }
}

/// Claude can renew its shared OAuth login. Other providers remain read-only.
struct LocalQuotaCredentials: QuotaCredentialSource {
    var claude = ClaudeCredentialRepository()

    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        if provider == .claude { return try claude.load() }
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if provider == .codex, let configured = env["CODEX_HOME"], configured.hasPrefix("/") {
            base = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            base = home.appendingPathComponent(provider == .gemini ? ".gemini" : ".codex", isDirectory: true)
        }
        let path = base.appendingPathComponent(provider == .gemini ? "oauth_creds.json" : "auth.json")
        if FileManager.default.fileExists(atPath: path.path) {
            guard let data = try? Data(contentsOf: path) else { throw QuotaFailure.credentialsUnavailable }
            return try Self.decode(data, provider: provider)
        }
        throw QuotaFailure.notSignedIn
        #else
        // Linux CI/tests must never inspect any actual credentials in their environment.
        throw QuotaFailure.notSignedIn
        #endif
    }

    func saveClaude(_ updated: QuotaCredential, replacing original: QuotaCredential) async throws -> QuotaCredential {
        try claude.save(updated, replacing: original)
    }

    static func decode(_ data: Data, provider: QuotaProvider) throws -> QuotaCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = (provider == .gemini ? root : root[provider == .claude ? "claudeAiOauth" : "tokens"]) as? [String: Any],
              let token = tokens[provider == .claude ? "accessToken" : "access_token"] as? String,
              !token.isEmpty, !token.contains("\r"), !token.contains("\n") else {
            throw QuotaFailure.notSignedIn
        }
        let account = tokens["account_id"] as? String
        if let account, account.contains("\r") || account.contains("\n") { throw QuotaFailure.notSignedIn }
        let expiry = QuotaParser.number(tokens[provider == .gemini ? "expiry_date" : "expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        var credential = QuotaCredential(accessToken: token, accountID: account, expiresAt: expiry)
        if provider == .claude, let refresh = tokens["refreshToken"] as? String,
           !refresh.isEmpty, !refresh.contains("\r"), !refresh.contains("\n") {
            credential.refreshToken = refresh
        }
        return credential
    }
}
