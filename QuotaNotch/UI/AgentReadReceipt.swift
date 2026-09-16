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

struct AgentSessionDetails: View {
    private let initialSession: AgentSession
    @ObservedObject private var store = AgentActivityStore.shared
    init(session: AgentSession) { initialSession = session }
    private var session: AgentSession { store.sessions.first { $0.identity == initialSession.identity } ?? initialSession }
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

            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }
}

/// Details participate in the parent list's scrolling; they never create another window or scroller.
struct AgentInlineDetails: View {
    let session: AgentSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AgentText.activity(session, now: AgentActivityStore.shared.now), systemImage: "circle.fill")
                .font(.system(size: 11)).foregroundStyle(AgentText.color(session.state))
            if !session.userPrompt.isEmpty {
                Text(AgentText.t("本轮输入", "Your request")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(session.userPrompt).font(.system(size: 11)).textSelection(.enabled)
            }
            if !session.activityDetail.isEmpty {
                Text(AgentText.t("最近活动", "Recent activity")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(session.activityDetail).font(.system(size: 11)).textSelection(.enabled)
            }
            Text(session.projectRoot.isEmpty ? session.cwd : session.projectRoot)
                .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct AgentNotchWindowSizing: NSViewRepresentable {
    let height: CGFloat
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) { view.targetHeight = height; view.resize() }
    final class SizingView: NSView {
        var targetHeight: CGFloat = 210
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resize() }
        func resize() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, abs(window.frame.height - self.targetHeight) > 0.5 else { return }
                var frame = window.frame
                frame.origin.y = frame.maxY - self.targetHeight
                frame.size.height = self.targetHeight
                window.setFrame(frame, display: true)
            }
        }
    }
}
