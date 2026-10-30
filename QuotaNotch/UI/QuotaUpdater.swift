// QuotaNotch additions, 2026. SPDX-License-Identifier: GPL-3.0-only
import Combine
import Sparkle
import SwiftUI

/// In-app updates through Sparkle. The feed is `appcast.xml` on the latest GitHub release;
/// every update is checked against the EdDSA public key in Info.plist before it installs.
/// The app is ad-hoc signed, so that key is what proves an update came from this project.
@MainActor
final class QuotaUpdater: ObservableObject {
    static let shared = QuotaUpdater()

    @Published private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController?

    /// False when this build carries no feed or key (for example local developer builds).
    var available: Bool { controller != nil }

    private init() {
        #if SETTINGS_PREVIEW
        controller = nil
        #else
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        if key.isEmpty || feed.isEmpty {
            controller = nil
        } else {
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            self.controller = controller
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        }
        #endif
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyInstalls: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyDownloadsUpdates = newValue }
    }
}

/// "Check for Updates…", for menus and settings.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = QuotaUpdater.shared
    var body: some View {
        Button("检查更新…") { updater.checkForUpdates() }
            .disabled(!updater.canCheck)
    }
}

/// The update settings in About.
struct UpdateSettingsSection: View {
    @ObservedObject private var updater = QuotaUpdater.shared
    var body: some View {
        Section("更新") {
            if updater.available {
                Toggle("自动检查更新", isOn: Binding(get: { updater.automaticallyChecks },
                                                set: { updater.automaticallyChecks = $0 }))
                Toggle("自动下载并安装更新", isOn: Binding(get: { updater.automaticallyInstalls },
                                                   set: { updater.automaticallyInstalls = $0 }))
                    .disabled(!updater.automaticallyChecks)
                CheckForUpdatesButton()
                Text("更新包会先校验签名再安装。应用尚未经过 Apple 公证，更新后可能需要重新授予辅助功能权限。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("这个版本不支持应用内更新，请从 GitHub 下载新版本。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Link("查看所有版本", destination: URL(string: "https://github.com/ApisXia/QuotaNotch/releases")!)
        }
    }
}
