// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Foundation
#if os(macOS)
import Security
import Darwin
#endif

enum ClaudeCredentialLocation: Sendable, Equatable {
    case file(URL)
    case keychain(String)
}

protocol ClaudeCredentialIO: Sendable {
    func read(_ location: ClaudeCredentialLocation) throws -> Data
    /// Return the current data if another writer has changed it before this write.
    func replace(_ location: ClaudeCredentialLocation, expected: Data, updated: Data) throws -> Data
}

struct ClaudeCredentialRepository: Sendable {
    var io: any ClaudeCredentialIO = SystemClaudeCredentialIO()
    var home = FileManager.default.homeDirectoryForCurrentUser
    var environment = ProcessInfo.processInfo.environment
    var now: @Sendable () -> Date = { Date() }

    var locations: [ClaudeCredentialLocation] {
        let base = environment["CLAUDE_CONFIG_DIR"].flatMap {
            $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil
        } ?? home.appendingPathComponent(".claude", isDirectory: true)
        return [.file(base.appendingPathComponent(".credentials.json").resolvingSymlinksInPath()),
                .keychain("Claude Code-credentials")]
    }

    func load() throws -> QuotaCredential {
        var candidates: [QuotaCredential] = []
        var unavailable = false
        for location in locations {
            do {
                var credential = try LocalQuotaCredentials.decode(io.read(location), provider: .claude)
                credential.location = location
                candidates.append(credential)
            } catch QuotaFailure.credentialsUnavailable { unavailable = true }
            catch { continue }
        }
        guard !candidates.isEmpty else {
            throw unavailable ? QuotaFailure.credentialsUnavailable : QuotaFailure.notSignedIn
        }
        let date = now()
        // A stale or malformed file must not hide the current Keychain login.
        return candidates.sorted { a, b in
            let aValid = a.expiresAt.map { $0 > date } ?? true
            let bValid = b.expiresAt.map { $0 > date } ?? true
            if aValid != bValid { return aValid }
            if a.expiresAt != b.expiresAt {
                return (a.expiresAt ?? .distantFuture) > (b.expiresAt ?? .distantFuture)
            }
            return a.refreshToken != nil && b.refreshToken == nil
        }[0]
    }

    func save(_ updated: QuotaCredential, replacing original: QuotaCredential) throws -> QuotaCredential {
        guard let location = original.location else { throw QuotaFailure.credentialsUnavailable }
        let selected = try load()
        guard selected == original else { return selected }
        let data = try io.read(location)
        var current = try LocalQuotaCredentials.decode(data, provider: .claude)
        current.location = location
        // Claude Code may have refreshed or changed accounts during the HTTP request.
        guard current == original else { return try load() }
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            throw QuotaFailure.credentialsUnavailable
        }
        oauth["accessToken"] = updated.accessToken
        oauth["refreshToken"] = updated.refreshToken
        oauth["expiresAt"] = updated.expiresAt.map { $0.timeIntervalSince1970 * 1000 }
        root["claudeAiOauth"] = oauth
        // Preserve scopes, subscription metadata and any unmodeled fields.
        let replacement = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let persisted = try io.replace(location, expected: data, updated: replacement)
        var result = try LocalQuotaCredentials.decode(persisted, provider: .claude)
        result.location = location
        return result
    }
}

struct SystemClaudeCredentialIO: ClaudeCredentialIO {
    func read(_ location: ClaudeCredentialLocation) throws -> Data {
        #if os(macOS)
        switch location {
        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { throw QuotaFailure.notSignedIn }
            guard let data = try? Data(contentsOf: url) else { throw QuotaFailure.credentialsUnavailable }
            return data
        case .keychain(let service):
            var query = keychainQuery(service)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { throw QuotaFailure.notSignedIn }
            guard status == errSecSuccess, let data = result as? Data else {
                throw QuotaFailure.credentialsUnavailable
            }
            return data
        }
        #else
        // CI never inspects a runner's actual login.
        throw QuotaFailure.notSignedIn
        #endif
    }

    func replace(_ location: ClaudeCredentialLocation, expected: Data, updated: Data) throws -> Data {
        #if os(macOS)
        let current = try read(location)
        guard current == expected else { return current }
        switch location {
        case .file(let url):
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".quotanotch-oauth-\(UUID().uuidString)")
            let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw QuotaFailure.credentialsUnavailable }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
            do { try handle.write(contentsOf: updated); try handle.synchronize() }
            catch { throw QuotaFailure.credentialsUnavailable }
            let latest = try read(location)
            guard latest == expected else { return latest }
            guard rename(temporary.path, url.path) == 0 else { throw QuotaFailure.credentialsUnavailable }
        case .keychain(let service):
            // Update exactly the item we read, even if the service has multiple accounts.
            var query = keychainQuery(service)
            query[kSecReturnData as String] = true
            query[kSecReturnPersistentRef as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let values = item as? [String: Any],
                  let reference = values[kSecValuePersistentRef as String] as? Data,
                  let latest = values[kSecValueData as String] as? Data else {
                throw QuotaFailure.credentialsUnavailable
            }
            guard latest == expected else { return latest }
            let status = SecItemUpdate([kSecValuePersistentRef as String: reference] as CFDictionary,
                [kSecValueData as String: updated] as CFDictionary)
            guard status == errSecSuccess else { throw QuotaFailure.credentialsUnavailable }
        }
        // These checks narrow the cross-process race; Claude Code does not share our lock.
        return try read(location)
        #else
        throw QuotaFailure.credentialsUnavailable
        #endif
    }

    #if os(macOS)
    private func keychainQuery(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }
    #endif
}
