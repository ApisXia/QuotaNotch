// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Connects QuotaNotch to Claude Code's status line, the only source of Claude quota.
@MainActor final class ClaudeConnection: ObservableObject {
    static let shared = ClaudeConnection()
    @Published private(set) var installed = false
    @Published private(set) var busy = false
    @Published var message: String?

    var settingsURL: URL { AgentActivityStore.shared.claudeHome.appendingPathComponent("settings.json") }

    func check() {
        installed = ClaudeStatusLineConfiguration.isInstalled(try? Data(contentsOf: settingsURL))
    }

    func setConnected(_ connect: Bool) {
        busy = true
        defer { busy = false; check() }
        do {
            if connect { try AgentHookHelper.installBundledCopy() }
            let helper = AgentHookHelper.installedURL.path
            let usage = ClaudeStatusLineUsage.defaultDirectory.path
            try FileManager.default.createDirectory(atPath: usage, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try ConfigurationFileWriter.update(settingsURL,
                backup: AgentActivityStore.support.appendingPathComponent("claude-hooks-before-quotanotch.json")) { previous in
                connect ? try ClaudeStatusLineConfiguration.installing(previous, helper: helper, usageDirectory: usage)
                        : try ClaudeStatusLineConfiguration.removing(previous)
            }
            message = nil
            if connect { Task { await QuotaNotchStore.shared.refresh(providerOnly: .claude) } }
        } catch ConfigurationFileWriter.Failure.changedDuringEdit {
            message = QuotaText.localized("Claude Code 的设置刚被修改，请再试一次。")
        } catch CocoaError.fileReadCorruptFile {
            message = QuotaText.localized("Claude Code 的 settings.json 不是有效的 JSON，未作修改。")
        } catch CocoaError.fileReadNoSuchFile {
            message = QuotaText.localized("这个 QuotaNotch 版本缺少状态栏组件，请使用 Releases 中的安装包。")
        } catch {
            message = error.localizedDescription
        }
    }
}
