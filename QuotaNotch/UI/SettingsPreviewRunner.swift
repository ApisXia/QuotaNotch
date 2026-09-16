// SPDX-License-Identifier: GPL-3.0-only
// Compiled only in the separate CI preview build, never in the installable app.
#if SETTINGS_PREVIEW
import AppKit
import SwiftUI
import Defaults
import EventKit

@main
struct SettingsPreviewRunner {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let language = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        let output = URL(fileURLWithPath: "build/Settings-previews/\(language)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Old manual sizing preferences must no longer affect the actual screen layout.
        UserDefaults.standard.set(15, forKey: "notchHeight")
        UserDefaults.standard.set(10, forKey: "nonNotchHeight")
        let automaticSize = getClosedNotchSize()
        UserDefaults.standard.set(45, forKey: "notchHeight")
        UserDefaults.standard.set(40, forKey: "nonNotchHeight")
        precondition(getClosedNotchSize() == automaticSize, "Legacy manual heights changed automatic sizing")
        Defaults[.showCalendar] = true
        Defaults[.useCustomAccentColor] = true
        Defaults[.enableSneakPeek] = true
        Defaults[.mediaController] = .youtubeMusic
        QuotaNotchStore.shared.configureSettingsPreview(paused: false)
        let store = QuotaNotchStore.shared
        let manual = store.pins.selected
        store.setProvider(.claude, enabled: false)
        precondition(store.pins.selected == manual && store.activePin == nil, "Pausing a service must preserve its manual choice without displaying it")
        store.configureSettingsPreview(paused: false)
        let calendar = CalendarManager.shared
        calendar.calendarAuthorizationStatus = .fullAccess
        calendar.reminderAuthorizationStatus = .notDetermined
        calendar.eventCalendars = (0..<4).map { index in
            CalendarModel(id: "preview-\(index)", account: "Preview",
                title: index == 0 ? "A very long shared calendar name — design reviews, planning and project milestones" : "Calendar \(index + 1)",
                color: .systemBlue, isSubscribed: false, isReminder: false)
        }
        for width: CGFloat in [700, 900] {
            for page in ["General", "Quota", "Activity", "Media", "Calendar", "Appearance", "System", "About"] {
                UserDefaults.standard.set(page, forKey: "settingsSelectedTab")
                try capture(SettingsView().environment(\.locale, Locale(identifier: language)), width: width,
                            name: "\(page)-\(Int(width))", output: output)
            }
        }
        Defaults[.mediaController] = .nowPlaying
        try capture(Media().formStyle(.grouped).environment(\.locale, Locale(identifier: language)), width: 500,
                    name: "Media-fallback", output: output)
        QuotaNotchStore.shared.configureSettingsPreview(paused: true)
        try capture(QuotaPreferences().formStyle(.grouped).environment(\.locale, Locale(identifier: language)), width: 500,
                    name: "Quota-paused", output: output)
        let permissionStates: [SettingsAccessState] = [.notRequested, .allowed, .denied, .restricted, .limited, .unavailable]
        try capture(Form {
            ForEach(Array(permissionStates.enumerated()), id: \.offset) { item in
                Section { SettingsPermissionNotice(state: item.element, action: {}) }
            }
        }.formStyle(.grouped).environment(\.locale, Locale(identifier: language)), width: 500,
                    name: "Permissions", output: output)
        let activity = AgentActivityStore.shared
        let now = Date()
        let fixtureStates: [AgentRunState] = [.waiting, .waiting, .running, .running, .running, .completed, .failed, .interrupted, .unknown]
        let fixtures = fixtureStates.enumerated().map { index, state -> AgentSession in
            var s = AgentSession(id: String(format: "11111111-1111-4111-8111-%012d", index))
            s.title = index == 0 ? AgentText.t("统一英文设置界面布局与多项目任务状态", "Align English settings and verify concurrent project task states") : AgentText.t("任务 \(index + 1)：验证布局与恢复逻辑", "Task \(index + 1): verify layout and recovery")
            s.cwd = "/Users/demo/Projects/\(index % 3)/src"
            s.projectRoot = "/Users/demo/Projects/\(index % 3)"
            s.projectName = ["QuotaNotch", "A project with a deliberately long name", "Website"][index % 3]
            s.provider = index % 3 == 1 ? .claude : .codex
            s.userPrompt = AgentText.t("检查英文布局和并行任务状态", "Check English layout and parallel task states")
            s.state = state; s.surface = index % 2 == 0 ? .desktop : .vscode
            s.tool = index % 2 == 0 ? "apply_patch" : "exec_command"
            if state == .waiting && index == 0 { s.waitingCallID = "preview-question" }
            s.turnID = "one"; s.startedAt = now.addingTimeInterval(-Double(150 + index * 90))
            s.updatedAt = now.addingTimeInterval(-Double(index * 40))
            if !state.isActive { s.finishedAt = now.addingTimeInterval(-30) }
            return s
        }
        activity.configurePreview(fixtures)
        precondition(activity.running == 3 && activity.waiting == 2)
        activity.markAllRead(); precondition(activity.unread.isEmpty)
        activity.configurePreview(fixtures)
        activity.dismissFinished(); precondition(activity.visible.count == 5)
        activity.configurePreview(fixtures)
        for width: CGFloat in [760, 1000] {
            for dark in [true, false] {
                try capture(AgentActivityView().preferredColorScheme(dark ? .dark : .light), width: width,
                            name: "Tasks-\(Int(width))-\(dark ? "dark" : "light")", output: output)
            }
        }
        for session in fixtures.prefix(2) {
            try capture(AgentSessionDetails(session: session), width: 520,
                        name: "Task-details-\(session.provider.rawValue)", output: output, height: 430)
        }
        try captureNotchSwitching(output: output)
        try captureTaskPanel(output: output, fixtures: fixtures)
        for dark in [true, false] {
            try capture(VStack(alignment: .leading, spacing: 12) {
                ForEach([AgentRunState.running, .waiting, .completed, .failed, .interrupted, .unknown], id: \.self) { state in
                    HStack(spacing: 14) {
                        AgentPaperGlyph(kind: AgentPaperGlyph.kind(state), running: state == .running, accent: AgentText.color(state))
                        Text(AgentText.state(state)).font(.system(size: 12)).foregroundStyle(AgentText.color(state))
                        Spacer()
                        Text("Project · Codex").font(.system(size: 12)).foregroundStyle(.primary)
                    }
                }
            }.padding(20).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(dark ? .dark : .light),
                width: 380, name: "Task-state-colors-\(dark)", output: output, height: 220)
        }
        var recent = fixtures[2]
        recent.updatedAt = now; recent.tool = "apply_patch"
        precondition(AgentText.activity(recent, now: now).contains(AgentText.t("修改文件", "file edit")))
        precondition(AgentText.activity(recent, now: now.addingTimeInterval(121)) == AgentText.t("暂时无新活动", "No recent activity"))
        recent.state = .completed
        precondition(!AgentText.activity(recent, now: now).contains(AgentText.t("修改文件", "file edit")))
        for height: CGFloat in [24, 32, 38] {
            let metrics = NotchModuleMetrics(widgetWidth: QuotaCompactMetrics.iconSize(height: height))
            try capture(HStack(spacing: 16) {
                ForEach(["0", "42", "100", "99+"], id: \.self) { number in
                    HStack(spacing: 6) {
                        NotchMinimalLabel(metrics: metrics, number: number) {
                            QuotaBrandMark(brand: .claude)
                                .frame(width: metrics.minimalIconSize, height: metrics.minimalIconSize)
                        }
                        NotchMinimalLabel(metrics: metrics, number: number) {
                            AgentPaperGlyph(kind: .running, running: true)
                                .scaleEffect(metrics.minimalIconSize / 16)
                                .frame(width: metrics.minimalIconSize, height: metrics.minimalIconSize)
                        }
                    }
                    .overlay(alignment: .bottom) { Color.white.opacity(0.15).frame(height: 0.5) }
                }
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black).preferredColorScheme(.dark), width: 240,
                name: "Minimal-baselines-\(Int(height))", output: output, height: height)
            for expanded in [false, true] {
                activity.compactExpanded = expanded
                try capture(AgentCompactDock(primaryWidth: 24, height: height, open: {}) {
                    Text("62%").font(.system(size: 10)).foregroundStyle(.white)
                }.padding(.horizontal, 14).background(.black).preferredColorScheme(.dark), width: 180,
                    name: "Tasks-dock-\(Int(height))-\(expanded)", output: output, height: height)
            }
        }
        activity.compactExpanded = false
        activity.configurePreview([])
        try capture(AgentActivityView(), width: 760, name: "Tasks-empty", output: output)
        print("Rendered real settings and task monitor in English/Chinese, narrow/wide and light/dark layouts: \(language)")
    }

    /// Exercise the same window and painted shell while switching real tabs.
    /// A standalone task-view screenshot cannot catch a vertically centered shell.
    @MainActor private static func captureNotchSwitching(output: URL) throws {
        let vm = BoringViewModel()
        vm.hideOnClosed = false
        let coordinator = BoringViewCoordinator.shared
        coordinator.helloAnimationRunning = false
        QuotaNotchStore.shared.configureSettingsPreview(paused: false)
        QuotaNotchStore.shared.menuOpen = true // Keep the fixture open without simulating pointer input.
        defer { QuotaNotchStore.shared.menuOpen = false }
        var renderedModules: [String: String] = [:]
        var modeAudit: [[String: Any]] = []
        let host = NSHostingView(rootView: ContentView().environmentObject(vm)
            .onPreferenceChange(NotchModuleAuditKey.self) { renderedModules = $0 }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background(Color(red: 0.25, green: 0.15, blue: 0.35)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(windowSize)
        window.orderFront(nil)
        vm.open()
        for headerHeight: CGFloat in [24, 32, 38] {
            vm.closedNotchSize.height = headerHeight
            for (index, tab) in [NotchViews.home, .activity, .aiUsage, .activity].enumerated() {
                coordinator.currentView = tab
                settle()
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Missing notch bitmap") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: output.appendingPathComponent("Notch-switch-\(Int(headerHeight))-\(index).png"))
                precondition(vm.notchState == .open, "Notch fixture unexpectedly closed")
                // Sample the reserved camera area, away from tab highlights and battery controls.
                // The active third tab occupies x=160; its gray capsule is not a screen gap.
                for fraction in [0.44, 0.5, 0.56] {
                    let color = bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * fraction), y: 2)!.usingColorSpace(.deviceRGB)!
                    precondition(max(color.redComponent, max(color.greenComponent, color.blueComponent)) < 0.06,
                                 "Notch detached after switching tab \(index), header \(headerHeight)")
                }
            }
        }
        let activity = AgentActivityStore.shared
        let fixtures = activity.sessions
        let receipts = descendants(host).compactMap { $0 as? AgentReadReceipt.ReceiptView }
        precondition(!receipts.isEmpty, "Task rows have no read receipts")
        activity.notchReadEnabled = false
        let unreadBefore = activity.unread.count
        for receipt in receipts { receipt.visibleSince = Date().addingTimeInterval(-2); receipt.check() }
        precondition(activity.unread.count == unreadBefore, "Hover preview marked tasks read")
        activity.notchReadEnabled = true
        for receipt in receipts { receipt.visibleSince = Date().addingTimeInterval(-2); receipt.check() }
        precondition(activity.unread.count < unreadBefore, "Explicitly opened visible rows were not read")
        activity.configurePreview(fixtures)
        activity.notchReadEnabled = false
        vm.close()
        var compactWidths: [String: Int] = [:]
        func blackWidth(_ bitmap: NSBitmapImageRep) -> Int {
            let row = max(1, Int(5 * CGFloat(bitmap.pixelsHigh) / host.bounds.height))
            let points = (0..<bitmap.pixelsWide).filter { x in
                guard let c = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                return max(c.redComponent, max(c.greenComponent, c.blueComponent)) < 0.06
            }
            return (points.last ?? 0) - (points.first ?? 0)
        }
        // Expectations describe presence, not the implementation's compactExpanded flag.
        let cases: [(name: String, quota: Bool, music: Bool, tasks: Bool)] = [
            ("quota", true, false, true), ("combined", true, true, true),
            ("music", false, true, true), ("tasks", false, false, true),
            ("quota-only", true, false, false), ("music-only", false, true, false),
            ("quota-music", true, true, false), ("empty", false, false, false)
        ]
        for scenario in cases {
            let layout = scenario.name
            let suffix = layout == "quota" ? "" : "-" + layout
            QuotaNotchStore.shared.configureSettingsPreview(paused: !scenario.quota)
            MusicManager.shared.isPlaying = scenario.music
            MusicManager.shared.isPlayerIdle = !scenario.music
            activity.configurePreview(scenario.tasks ? fixtures : [])
            coordinator.musicLiveActivityEnabled = true
        for headerHeight: CGFloat in [24, 32, 38] {
            vm.closedNotchSize.height = headerHeight
            for expanded in [false, true] {
                AgentActivityStore.shared.compactExpanded = expanded
                settle(); host.layoutSubtreeIfNeeded()
                let shared = scenario.quota && scenario.music && scenario.tasks
                var expected: [String: String] = [:]
                if scenario.quota { expected["quota"] = shared && expanded ? "minimal" : "widget" }
                if scenario.music { expected["music"] = "widget" }
                if scenario.tasks { expected["task"] = shared && !expanded ? "minimal" : "widget" }
                if shared { expected["divider"] = "switchable" }
                verifyPresentation(renderedModules == expected,
                    "Wrong presentation in \(layout), height \(headerHeight), selection \(expanded): \(renderedModules), expected \(expected)")
                modeAudit.append(["case": layout, "height": headerHeight, "taskSelected": expanded, "rendered": renderedModules])
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Notch-closed-\(Int(headerHeight))-\(expanded)\(suffix).png"))
                let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2)!.usingColorSpace(.deviceRGB)!
                precondition(max(color.redComponent, max(color.greenComponent, color.blueComponent)) < 0.06, "Closed notch detached")
                if scenario.tasks {
                    let key = layout + String(Int(headerHeight))
                    if !expanded { compactWidths[key] = blackWidth(bitmap) }
                    else { precondition(abs(blackWidth(bitmap) - compactWidths[key]!) <= 1, "Swapping widget/minimal changed the total width") }
                }
            }
            if layout == "combined" {
                activity.configurePreview([]); activity.compactExpanded = false
                settle(); host.layoutSubtreeIfNeeded()
                let baseline = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: baseline)
                let scale = CGFloat(baseline.pixelsWide) / host.bounds.width
                let budget = NotchModuleMetrics(widgetWidth: QuotaCompactMetrics.iconSize(height: headerHeight)).additionalWidth
                precondition(CGFloat(compactWidths[layout + String(Int(headerHeight))]! - blackWidth(baseline)) <= budget * scale + 2,
                             "Minimal exceeded its fixed additional-width budget")
                try baseline.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Notch-closed-\(Int(headerHeight))-widget-only.png"))
                activity.configurePreview(fixtures)
            }
        }
        }
        QuotaNotchStore.shared.configureSettingsPreview(paused: false)
        activity.configurePreview(fixtures)
        for headerHeight: CGFloat in [24, 32, 38] {
            vm.closedNotchSize.height = headerHeight
            for expanded in [false, true] {
                activity.compactExpanded = expanded
                for playback in ["playing", "paused", "idle", "resumed"] {
                    MusicManager.shared.isPlaying = playback == "playing" || playback == "resumed"
                    MusicManager.shared.isPlayerIdle = playback == "idle"
                    settle(); host.layoutSubtreeIfNeeded()
                    let expected = playback == "idle"
                        ? ["quota": "widget", "task": "widget"]
                        : ["music": "widget", "quota": expanded ? "minimal" : "widget",
                           "task": expanded ? "widget" : "minimal", "divider": "switchable"]
                    verifyPresentation(renderedModules == expected, "Playback transition \(playback) retained the wrong presentation: \(renderedModules)")
                    modeAudit.append(["case": playback, "height": headerHeight, "taskSelected": expanded, "rendered": renderedModules])
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Notch-transition-\(Int(headerHeight))-\(expanded)-\(playback).png"))
                }
            }
        }
        try JSONSerialization.data(withJSONObject: modeAudit, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Notch-presentation-audit.json"))
        print("Verified \(modeAudit.count) actual rendered presentations, including playback transitions")
        MusicManager.shared.isPlaying = false
        MusicManager.shared.isPlayerIdle = true
        AgentActivityStore.shared.compactExpanded = false
        window.orderOut(nil); window.contentView = nil; window.close()
        vm.destroy()
    }

    @MainActor private static func captureTaskPanel(output: URL, fixtures: [AgentSession]) throws {
        let store = AgentActivityStore.shared
        store.configurePreview(fixtures); store.panelExpanded = false; store.expandedTaskID = nil
        store.filter = .all; store.retainNotchOrder(); store.notchReadEnabled = false
        let vm = BoringViewModel(); vm.hideOnClosed = false
        let coordinator = BoringViewCoordinator.shared
        coordinator.currentView = .activity
        QuotaNotchStore.shared.menuOpen = true
        defer { QuotaNotchStore.shared.menuOpen = false }
        let host = NSHostingView(rootView: ContentView().environmentObject(vm)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        vm.open(); settle(); host.layoutSubtreeIfNeeded()
        let top = window.frame.maxY, width = window.frame.width
        let windowCount = NSApp.windows.filter(\.isVisible).count
        let initialHeight = vm.notchSize.height
        func snapshot(_ name: String) throws {
            settle(); host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            verifyPresentation(abs(window.frame.maxY - top) < 1 && window.frame.width == width, "Task panel moved away from its top edge or changed width")
            verifyPresentation(NSApp.windows.filter(\.isVisible).count == windowCount, "Task interaction opened an extra window")
        }
        try snapshot("Task-panel-compact")
        let unread = store.unread.count
        store.selectNotchFilter(.all)
        try snapshot("Task-panel-all")
        verifyPresentation(vm.notchSize.height > initialHeight, "All did not expand the same panel")
        verifyPresentation(store.unread.count == unread, "Selecting All marked unseen tasks read")
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        verifyPresentation(scrolls.contains { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height }, "All tasks are not scrollable")
        store.showDetails(fixtures[0])
        try snapshot("Task-panel-inline")
        verifyPresentation(store.expandedTaskID == fixtures[0].identity, "Details did not expand inline")
        store.toggleInlineDetails(fixtures[1])
        try snapshot("Task-panel-second-inline")
        verifyPresentation(store.expandedTaskID == fixtures[1].identity, "Only one inline row should be expanded")
        let originalOrder = store.notchSessions.map(\.identity)
        var newTask = fixtures[0]
        newTask.id = "22222222-2222-4222-8222-222222222222"
        newTask.updatedAt = Date()
        store.configurePreview([newTask] + fixtures); store.retainNotchOrder()
        verifyPresentation(Array(store.notchSessions.prefix(originalOrder.count)).map(\.identity) == originalOrder, "A new task reordered visible rows")
        coordinator.currentView = .home
        try snapshot("Task-panel-back-home")
        verifyPresentation(vm.notchSize.height == openNotchSize.height, "Leaving tasks did not restore the standard panel height")
        vm.close(); settle()
        verifyPresentation(abs(window.frame.height - windowSize.height) < 1, "Closing left an oversized input window")
        window.orderOut(nil); window.contentView = nil; window.close(); vm.destroy()
        store.configurePreview(fixtures); store.expandedTaskID = nil; store.panelExpanded = false
    }

    @MainActor private static func capture<V: View>(_ view: V, width: CGFloat, name: String, output: URL, height: CGFloat = 600) throws {
        let size = NSSize(width: width, height: height)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settle()
        let scrollViews = descendants(host).compactMap { $0 as? NSScrollView }
        // The sidebar has its own scroll view; select the widest one for page content.
        let scroll = scrollViews.max { $0.frame.width < $1.frame.width }
        let maxOffset = max(0, (scroll?.documentView?.bounds.height ?? 0) - (scroll?.contentView.bounds.height ?? 0))
        for (index, fraction) in [CGFloat(0), 0.5, 1].enumerated() {
            if index > 0 && maxOffset <= 1 { continue }
            scroll?.contentView.scroll(to: NSPoint(x: 0, y: maxOffset * fraction))
            if let scroll { scroll.reflectScrolledClipView(scroll.contentView) }
            settle()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Missing settings bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Missing settings PNG") }
            try png.write(to: output.appendingPathComponent("\(name)-\(index).png"))
        }
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
    private static func verifyPresentation(_ condition: Bool, _ message: @autoclosure () -> String) {
        guard condition else {
            let diagnostic = message()
            // Release optimization can omit precondition diagnostics; retain the failing scenario in CI.
            FileHandle.standardError.write(Data((diagnostic + "\n").utf8))
            fatalError(diagnostic)
        }
    }

    @MainActor private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
#endif
