// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The small event helper that Claude Code / Codex hooks run. Hooks point at a copy in
/// Application Support so moving the app does not break them.
enum AgentHookHelper {
    static var installedURL: URL { AgentActivityStore.support.appendingPathComponent("QuotaNotchMonitorHook") }
    static var bundledURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QuotaNotchMonitorHook") }

    static func installBundledCopy() throws {
        let fm = FileManager.default
        let binary = try Data(contentsOf: bundledURL)
        if (try? Data(contentsOf: installedURL)) == binary { return }
        try fm.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try binary.write(to: installedURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: installedURL.path)
    }

    /// After an app update, replace the copy that installed hooks run. Never creates one.
    static func refreshIfInstalled() {
        guard FileManager.default.fileExists(atPath: installedURL.path) else { return }
        try? installBundledCopy()
    }
}
