// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct QuotaCredential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let accessToken: String
    let accountID: String?
    let expiresAt: Date?
    var description: String { "QuotaCredential(<redacted>)" }
    var debugDescription: String { description }
}

protocol QuotaCredentialSource: Sendable {
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential
}

/// Read-only access to the Codex CLI login. Claude quota comes from Claude Code's status line
/// instead (see `ClaudeStatusLineUsage`), so no Claude credential is ever read or written.
struct LocalQuotaCredentials: QuotaCredentialSource {
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        guard provider == .codex else { throw QuotaFailure.notSignedIn }
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let configured = env["CODEX_HOME"], configured.hasPrefix("/") {
            base = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".codex", isDirectory: true)
        }
        let path = base.appendingPathComponent("auth.json")
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

    static func decode(_ data: Data, provider: QuotaProvider) throws -> QuotaCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.isEmpty, !token.contains("\r"), !token.contains("\n") else {
            throw QuotaFailure.notSignedIn
        }
        let account = tokens["account_id"] as? String
        if let account, account.contains("\r") || account.contains("\n") { throw QuotaFailure.notSignedIn }
        let expiry = QuotaParser.number(tokens["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return QuotaCredential(accessToken: token, accountID: account, expiresAt: expiry)
    }
}
