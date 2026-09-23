// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A short-lived, non-sliding cache for successful reads from the local Claude
/// credential source. The synchronous lock keeps cache access safe when the
/// source is called from multiple tasks without introducing an async lock hop.
final class ClaudeCredentialCache: @unchecked Sendable {
    static let defaultTTL: TimeInterval = 5 * 60

    private struct Entry {
        let credential: QuotaCredential
        let loadedAt: Date
    }

    private let lock = NSLock()
    private let ttl: TimeInterval
    private var entry: Entry?

    init(ttl: TimeInterval = ClaudeCredentialCache.defaultTTL) {
        self.ttl = max(0, ttl)
    }

    /// Reads through the cache while holding the same lock for the source read.
    /// This collapses concurrent misses into one file/keychain operation.
    func load(
        at now: Date,
        force: Bool = false,
        loader: () throws -> QuotaCredential
    ) throws -> QuotaCredential {
        lock.lock()
        defer { lock.unlock() }

        if !force, let entry {
            let age = now.timeIntervalSince(entry.loadedAt)
            if age >= 0, age < ttl { return entry.credential }
            self.entry = nil
        }
        do {
            let credential = try loader()
            entry = Entry(credential: credential, loadedAt: now)
            return credential
        } catch {
            self.entry = nil
            throw error
        }
    }

    /// Writes through the cache while holding the lock, so a reader cannot
    /// repopulate stale data while a renewal is being persisted.
    func save(
        at now: Date,
        writer: () throws -> QuotaCredential
    ) throws -> QuotaCredential {
        lock.lock()
        defer { lock.unlock() }

        do {
            let credential = try writer()
            entry = Entry(credential: credential, loadedAt: now)
            return credential
        } catch {
            self.entry = nil
            throw error
        }
    }

    func value(at now: Date) -> QuotaCredential? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry else { return nil }
        let age = now.timeIntervalSince(entry.loadedAt)
        guard age >= 0, age < ttl else {
            self.entry = nil
            return nil
        }
        return entry.credential
    }

    func store(_ credential: QuotaCredential, loadedAt: Date) {
        lock.lock()
        entry = Entry(credential: credential, loadedAt: loadedAt)
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        entry = nil
        lock.unlock()
    }
}

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
    /// Invalidates any local credential cache after an auth failure or write.
    /// Existing sources can keep the default no-op implementation.
    func invalidateClaudeCache()
    /// Forces a source read, bypassing any local credential cache.
    func reloadClaude() async throws -> QuotaCredential
}

extension QuotaCredentialSource {
    func saveClaude(_ updated: QuotaCredential, replacing original: QuotaCredential) async throws -> QuotaCredential {
        throw QuotaFailure.credentialsUnavailable
    }

    func invalidateClaudeCache() {}

    func reloadClaude() async throws -> QuotaCredential {
        invalidateClaudeCache()
        return try await load(.claude)
    }
}

/// Claude can renew its shared OAuth login. Other providers remain read-only.
struct LocalQuotaCredentials: QuotaCredentialSource {
    static let credentialCacheTTL: TimeInterval = ClaudeCredentialCache.defaultTTL

    let claude: ClaudeCredentialRepository
    private let cache: ClaudeCredentialCache
    private let clock: @Sendable () -> Date

    init(
        claude: ClaudeCredentialRepository = ClaudeCredentialRepository(),
        cacheTTL: TimeInterval = LocalQuotaCredentials.credentialCacheTTL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.claude = claude
        self.cache = ClaudeCredentialCache(ttl: cacheTTL)
        self.clock = clock
    }

    func load(_ provider: QuotaProvider) async throws -> QuotaCredential {
        if provider == .claude {
            return try cache.load(at: clock()) { try claude.load() }
        }
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
        try cache.save(at: clock()) { try claude.save(updated, replacing: original) }
    }

    func invalidateClaudeCache() {
        cache.invalidate()
    }

    func reloadClaude() async throws -> QuotaCredential {
        try cache.load(at: clock(), force: true) { try claude.load() }
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
