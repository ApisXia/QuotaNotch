// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Receipt is tied to the visible event version, not just the task id.
struct AgentReadReceipt: NSViewRepresentable {
    let session: AgentSession
    var notch = false
    func makeNSView(context: Context) -> ReceiptView { ReceiptView() }
    func updateNSView(_ view: ReceiptView, context: Context) { view.configure(session, notch: notch) }
    final class ReceiptView: NSView {
        var session: AgentSession?
        var notch = false
        var visibleSince: Date?
        var acknowledged = false
        var timer: Timer?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func configure(_ session: AgentSession, notch: Bool) {
            if self.session?.eventID != session.eventID { visibleSince = nil; acknowledged = false }
            self.session = session; self.notch = notch
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); timer?.invalidate(); timer = nil
            #if !SETTINGS_PREVIEW
            if window != nil { timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            } }
            #endif
        }
        func check() {
            guard !acknowledged, let session, let window, window.isVisible, !isHiddenOrHasHiddenAncestor,
                  (notch ? AgentActivityStore.shared.notchReadEnabled : window.isKeyWindow),
                  bounds.width > 1, bounds.height > 1,
                  visibleRect.width >= bounds.width * 0.8, visibleRect.height >= bounds.height * 0.8 else { visibleSince = nil; return }
            if visibleSince == nil { visibleSince = Date() }
            guard Date().timeIntervalSince(visibleSince!) >= 0.85 else { return }
            AgentActivityStore.shared.markRead(session); acknowledged = true
        }
        deinit { timer?.invalidate() }
    }
}

@MainActor enum AgentSessionDetailsWindow {
    private static var controller: NSWindowController?
    static func show(_ session: AgentSession) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = session.projectName; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AgentSessionDetails(session: session))
        controller?.close(); controller = NSWindowController(window: window)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct AgentSessionDetails: View {
    let session: AgentSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(AgentText.source(session)).font(.system(size: 13, weight: .medium))
                Text(session.displayTitle).font(.headline)
                Text(AgentText.state(session.state)).foregroundStyle(AgentText.color(session.state))
                if !session.userPrompt.isEmpty {
                    Text(AgentText.t("你本轮输入的内容", "Your latest request")).font(.caption).foregroundStyle(.secondary)
                    Text(session.userPrompt).font(.system(size: 12)).textSelection(.enabled)
                }
                if !session.activityDetail.isEmpty {
                    Text(AgentText.t("最近活动", "Recent activity")).font(.caption).foregroundStyle(.secondary)
                    Text(session.activityDetail).font(.system(size: 12)).textSelection(.enabled)
                }
                Text(session.cwd).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if session.provider == .claude {
                    Text(AgentText.t("此来源暂不支持直接跳回同一会话。可在原项目的终端恢复这个 Claude Code 会话。", "This source does not yet support returning directly to the exact session. Resume this Claude Code session in a terminal at its project."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(AgentText.t("复制恢复命令", "Copy resume command")) {
                        guard UUID(uuidString: session.id) != nil else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("claude --resume " + session.id, forType: .string)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }
}
