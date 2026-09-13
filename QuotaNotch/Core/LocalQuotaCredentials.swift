// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if os(macOS)
import Security
#endif

struct QuotaCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let accessToken: String
    let accountID: String?
    let expiresAt: Date?
    var description: String { "QuotaCredential(<redacted>)" }
    var debugDescription: String { description }
}

protocol QuotaCredentialSource: Sendable {
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential
}

/// Read-only: never rotates tokens, overwrites CLI files, spawns a shell or logs secrets.
struct LocalQuotaCredentials: QuotaCredentialSource {
    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if provider == .codex, let configured = env["CODEX_HOME"], configured.hasPrefix("/") {
            base = URL(fileURLWithPath: configured, isDirectory: true)
        } else if provider == .claude, let configured = env["CLAUDE_CONFIG_DIR"], configured.hasPrefix("/") {
            base = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            base = home.appendingPathComponent(provider == .claude ? ".claude" : ".codex", isDirectory: true)
        }
        let path = base.appendingPathComponent(provider == .claude ? ".credentials.json" : "auth.json")
        if FileManager.default.fileExists(atPath: path.path) {
            guard let data = try? Data(contentsOf: path) else { throw QuotaFailure.credentialsUnavailable }
            return try Self.decode(data, provider: provider)
        }
        if provider == .claude {
            // One explicit service, never enumerate the user's Keychain.
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Claude Code-credentials",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound { throw QuotaFailure.notSignedIn }
            guard status == errSecSuccess, let data = value as? Data else {
                throw QuotaFailure.credentialsUnavailable
            }
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
              let tokens = root[provider == .claude ? "claudeAiOauth" : "tokens"] as? [String: Any],
              let token = tokens[provider == .claude ? "accessToken" : "access_token"] as? String,
              !token.isEmpty, !token.contains("\r"), !token.contains("\n") else {
            throw QuotaFailure.notSignedIn
        }
        let account = tokens["account_id"] as? String
        if let account, account.contains("\r") || account.contains("\n") { throw QuotaFailure.notSignedIn }
        let expiry = QuotaParser.number(tokens["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return QuotaCredential(accessToken: token, accountID: account, expiresAt: expiry)
    }
}
