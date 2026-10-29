// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Optional task-event hooks for Claude Code and Codex: they tell QuotaNotch promptly when a
/// task waits for approval. Basic task monitoring works without them.
@MainActor final class HookConnection: ObservableObject {
    static let shared = HookConnection()
    @Published private(set) var installed: [AgentProvider: Bool] = [:]
    @Published private(set) var busy = false
    @Published var message: [AgentProvider: String] = [:]

    func configHome(_ provider: AgentProvider) -> URL {
        provider == .codex ? AgentActivityStore.shared.home : AgentActivityStore.shared.claudeHome
    }
    func configFile(_ provider: AgentProvider) -> URL {
        configHome(provider).appendingPathComponent(provider == .codex ? "hooks.json" : "settings.json")
    }

    func check() {
        for provider in [AgentProvider.claude, .codex] {
            installed[provider] = AgentHookConfiguration.isInstalled(try? Data(contentsOf: configFile(provider)))
        }
    }

    func set(_ provider: AgentProvider, installed install: Bool) {
        busy = true
        defer { busy = false; check() }
        do {
            let support = AgentActivityStore.support
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let helper = AgentHookHelper.installedURL
            if install { try AgentHookHelper.installBundledCopy() }
            let eventDirectory = support.appendingPathComponent(provider == .codex ? "events" : "claude-events").path
            try ConfigurationFileWriter.update(configFile(provider),
                backup: support.appendingPathComponent("\(provider.rawValue)-hooks-before-quotanotch.json")) { previous in
                try AgentHookConfiguration.updating(previous, helper: install ? helper.path : nil,
                                                    eventDirectory: eventDirectory, provider: provider)
            }
            message[provider] = install
                ? QuotaText.localized(provider == .codex
                    ? "已安装。请在 Codex 中审阅并信任这些 hooks 后生效。"
                    : "已安装。新开的 Claude Code 会话会使用它；如有提示，请审阅并信任这些 hooks。")
                : nil
        } catch ConfigurationFileWriter.Failure.changedDuringEdit {
            message[provider] = QuotaText.localized("配置文件刚被其他程序修改，请再试一次。")
        } catch ConfigurationFileWriter.Failure.tooLarge {
            message[provider] = QuotaText.localized("配置文件过大，未作修改。")
        } catch CocoaError.fileReadCorruptFile {
            message[provider] = QuotaText.localized("配置文件不是有效的 JSON，未作修改。")
        } catch CocoaError.fileReadNoSuchFile {
            message[provider] = QuotaText.localized("这个 QuotaNotch 版本缺少状态栏组件，请使用 Releases 中的安装包。")
        } catch {
            message[provider] = error.localizedDescription
        }
    }

    func chooseCodexHome() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.showsHiddenFiles = true; panel.directoryURL = AgentActivityStore.shared.home
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "agentMonitorCodexHome")
            message[.codex] = QuotaText.localized("数据目录已保存，重启 QuotaNotch 后生效。")
        }
    }
}
