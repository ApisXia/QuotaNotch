// SPDX-License-Identifier: GPL-3.0-only
// Compiled only in the separate CI preview build, never in the installable app.
#if SETTINGS_PREVIEW
import AppKit
import SwiftUI
import Combine
import Defaults
import EventKit
import ImageIO
import UniformTypeIdentifiers

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
        let initialIDs = activity.visible.map(\.identity)
        let project = fixtures[0].groupID
        let otherUnread = Set(activity.unread.filter { $0.groupID != project }.map(\.eventID))
        activity.markAllRead(inProject: project)
        verifyPresentation(activity.unread.allSatisfy { $0.groupID != project }, "Project read left unread events in that project")
        verifyPresentation(Set(activity.unread.map(\.eventID)) == otherUnread, "Project read affected another project")
        activity.markAllRead()
        verifyPresentation(activity.unread.isEmpty && activity.visible.map(\.identity) == initialIDs,
                           "Bulk read removed history or left unread events")
        verifyPresentation(activity.running == 3 && activity.waiting == 2 && activity.attention.needsAction,
                           "Bulk read changed live states or hid waiting tasks")
        var nextEvent = fixtures[0]; nextEvent.turnID = "next-event"
        verifyPresentation(activity.isUnread(nextEvent), "Bulk read swallowed a later event from the same task")
        activity.markAllRead()
        verifyPresentation(activity.visible.map(\.identity) == initialIDs, "Repeated bulk read changed history")
        print("Verified bulk read scope, history retention, active/waiting states and later unread events")
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
        try captureTaskGlyphMotion(output: output)
        try verifyCatRubRegion()
        try captureCat(output: output, fixtures: fixtures)
        try captureNotchSwitching(output: output)
        try captureTaskPanel(output: output, fixtures: fixtures)
        for dark in [true, false] {
            try capture(VStack(alignment: .leading, spacing: 12) {
                ForEach([AgentRunState.running, .waiting, .completed, .failed, .interrupted, .unknown], id: \.self) { state in
                    HStack(spacing: 14) {
                        AgentPaperGlyph(state: state)
                        Text(AgentText.state(state)).font(.system(size: 12)).foregroundStyle(AgentText.color(state))
                        Spacer()
                        Text("Project · Codex").font(.system(size: 12)).foregroundStyle(.primary)
                    }
                }
            }.padding(20).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(dark ? .dark : .light),
                width: 380, name: "Task-state-colors-\(dark)", output: output, height: 220)
        }
        for reduced in [false, true] {
            try capture(VStack(alignment: .leading, spacing: 14) {
                ForEach(AgentRunState.allCases, id: \.self) { state in
                    HStack(spacing: 18) {
                        AgentTaskStateMark(state: state, animate: !reduced).frame(width: 12)
                        AgentTaskStateMark(state: state, animate: !reduced).scaleEffect(3).frame(width: 22, height: 22)
                        Text(AgentText.state(state)).font(.system(size: 11)).foregroundStyle(.white)
                        Spacer()
                    }
                }
            }.padding(16).background(.black).preferredColorScheme(.dark), width: 300,
                name: "Task-state-marks-\(reduced ? "still" : "motion")", output: output, height: 250)
        }
        var recent = fixtures[2]
        recent.updatedAt = now; recent.tool = "apply_patch"
        precondition(AgentText.activity(recent, now: now).contains(AgentText.t("修改文件", "file edit")))
        precondition(AgentText.activity(recent, now: now.addingTimeInterval(121)) == AgentText.t("暂时无新活动", "No recent activity"))
        recent.state = .completed
        precondition(!AgentText.activity(recent, now: now).contains(AgentText.t("修改文件", "file edit")))
        var noDetail = AgentSession(id: "no-detail", state: .failed)
        precondition(AgentText.context(noDetail, now: now) == nil && AgentText.detail(noDetail, now: now) == nil)
        noDetail.state = .waiting
        precondition(AgentText.context(noDetail, now: now) == nil)
        noDetail.waitingCallID = "question"
        precondition(AgentText.context(noDetail, now: now) == AgentText.t("等待回答", "Awaiting answer"))
        precondition(AgentText.relativeTime(now.addingTimeInterval(-720), now: now) == AgentText.t("12 分钟前", "12m ago"))
        for height: CGFloat in [24, 32, 38] {
            let metrics = NotchModuleMetrics(widgetWidth: QuotaCompactMetrics.iconSize(height: height))
            let samples: [Double?] = [nil, 0, 10, 42, 100]
            let states: [AgentRunState] = [.unknown, .failed, .waiting, .running, .completed]
            try capture(HStack(spacing: 16) {
                ForEach(0..<samples.count, id: \.self) { index in
                    HStack(spacing: 8) {
                        NotchMinimalIcon(metrics: metrics) {
                            MinimalQuotaGlyph(brand: .claude, percent: samples[index], size: metrics.minimalIconSize)
                        }
                        NotchMinimalIcon(metrics: metrics) {
                            AgentPaperGlyph(state: states[index])
                                .scaleEffect(metrics.minimalIconSize / 16)
                                .frame(width: metrics.minimalIconSize, height: metrics.minimalIconSize)
                        }
                    }
                }
            }.foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black).preferredColorScheme(.dark), width: 280,
                name: "Minimal-graphics-\(Int(height))", output: output, height: height)
            try capture(HStack(spacing: 24) {
                ForEach([QuotaProvider.claude, .codex, .gemini], id: \.self) { provider in
                    HStack(spacing: 8) {
                        MinimalQuotaGlyph(brand: provider.brand, percent: 65, size: metrics.minimalIconSize)
                        MinimalQuotaGlyph(brand: provider.brand, percent: 65, stale: true, size: metrics.minimalIconSize)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).preferredColorScheme(.dark),
                width: 220, name: "Minimal-brands-\(Int(height))", output: output, height: height)
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
        // Drive the full header row's event receiver, including blank space and the right side.
        coordinator.currentView = .home; settle(); host.layoutSubtreeIfNeeded()
        guard let swipe = descendants(host).compactMap({ $0 as? NotchTabSwipeRegion.Region }).first else {
            fatalError("The open panel has no header swipe region")
        }
        verifyPresentation(swipe.bounds.width >= openNotchSize.width * 0.7,
                           "Swipe region only covers the tabs instead of the full header row")
        verifyPresentation(abs(swipe.bounds.height - max(24, vm.effectiveClosedNotchHeight)) < 1,
                           "Header swipe region extends into the page body")
        let inside = swipe.convert(NSPoint(x: swipe.bounds.midX, y: swipe.bounds.midY), to: nil)
        let outside = swipe.convert(NSPoint(x: swipe.bounds.minX - 20, y: swipe.bounds.minY - 20), to: nil)
        verifyPresentation(coordinator.currentView == .home, "Swipe fixture did not start on Home")
        swipe.handleScroll(x: -30, y: 0, at: 1, phase: .began, eventWindow: window, location: outside)
        verifyPresentation(coordinator.currentView == .home, "A swipe outside the header row changed pages")
        swipe.handleScroll(x: 0, y: 30, at: 2, phase: .began, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .home, "Vertical scrolling changed tabs")
        for index in 0..<5 {
            swipe.handleScroll(x: -3, y: 0, at: 3 + Double(index) * 0.01,
                               phase: index == 0 ? .began : .changed, eventWindow: window, location: inside)
        }
        verifyPresentation(coordinator.currentView == .aiUsage, "A slow swipe did not select Quota")
        swipe.handleScroll(x: -40, y: 0, at: 4, phase: .changed, momentum: true, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .aiUsage, "Momentum skipped a tab")
        let unreadBeforeSwipe = AgentActivityStore.shared.unread.count
        swipe.handleScroll(x: -20, y: 0, at: 5, phase: .began, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .activity && AgentActivityStore.shared.notchReadEnabled,
                           "Swiping to Tasks did not use explicit opening behavior")
        verifyPresentation(AgentActivityStore.shared.unread.count == unreadBeforeSwipe, "Swiping instantly read unseen tasks")
        swipe.handleScroll(x: -20, y: 0, at: 6, phase: .began, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .activity, "Swiping at the last tab wrapped around")
        swipe.handleScroll(x: 20, y: 0, at: 7, phase: .began, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .aiUsage && !AgentActivityStore.shared.notchReadEnabled,
                           "Swiping back did not leave Tasks correctly")
        for (index, fraction) in [CGFloat(0.05), 0.5, 0.95].enumerated() {
            coordinator.currentView = .home
            let point = swipe.convert(NSPoint(x: swipe.bounds.minX + swipe.bounds.width * fraction,
                                              y: swipe.bounds.midY), to: nil)
            swipe.handleScroll(x: -20, y: 0, at: 8 + Double(index) * 2, phase: .began, eventWindow: window, location: point)
            verifyPresentation(coordinator.currentView == .aiUsage, "Header swipe failed at horizontal position \(fraction)")
            swipe.handleScroll(x: 20, y: 0, at: 9 + Double(index) * 2, phase: .began, eventWindow: window, location: point)
            verifyPresentation(coordinator.currentView == .home, "Reverse header swipe failed at horizontal position \(fraction)")
        }
        for y in [swipe.bounds.minY - 20, swipe.bounds.maxY + 20] {
            let point = swipe.convert(NSPoint(x: swipe.bounds.midX, y: y), to: nil)
            swipe.handleScroll(x: -20, y: 0, at: 20, phase: .began, eventWindow: window, location: point)
            verifyPresentation(coordinator.currentView == .home, "A swipe above or below the header changed tabs")
        }
        coordinator.currentView = .activity; settle(); host.layoutSubtreeIfNeeded()
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
                if scenario.tasks && !scenario.quota && !scenario.music { expected["task-summary"] = "widget" }
                verifyPresentation(renderedModules == expected,
                    "Wrong presentation in \(layout), height \(headerHeight), selection \(expanded): \(renderedModules), expected \(expected)")
                modeAudit.append(["case": layout, "height": headerHeight, "taskSelected": expanded, "rendered": renderedModules])
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Notch-closed-\(Int(headerHeight))-\(expanded)\(suffix).png"))
                let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2)!.usingColorSpace(.deviceRGB)!
                precondition(max(color.redComponent, max(color.greenComponent, color.blueComponent)) < 0.06, "Closed notch detached")
                if layout == "tasks" {
                    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                    let budget = NotchModuleMetrics(widgetWidth: QuotaCompactMetrics.iconSize(height: headerHeight)).additionalWidth
                    let widgetPairWidth = compactWidths["music" + String(Int(headerHeight))]!
                    verifyPresentation(CGFloat(blackWidth(bitmap) - widgetPairWidth) <= budget * scale + 2,
                                       "Task-only list exceeded the widget plus minimal width budget")
                }
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

    /// Actual production glyphs at their real sizes, sampled into an animated cloud artifact.
    @MainActor private static func captureTaskGlyphMotion(output: URL) throws {
        func board(_ elapsed: Double) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(AgentText.t("任务状态", "Task states")).frame(width: 100, alignment: .leading)
                    ForEach(["20", "14", "10", "6", "Still", "2×"], id: \.self) { label in
                        Text(label).frame(width: 38)
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(AgentRunState.allCases, id: \.self) { state in
                    HStack(spacing: 8) {
                        Text(AgentText.state(state)).font(.system(size: 11)).frame(width: 100, alignment: .leading)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(20.0 / 16).frame(width: 38, height: 28)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(14.0 / 16).frame(width: 38, height: 28)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(10.0 / 16).frame(width: 38, height: 28)
                        AgentTaskStateMark(state: state, previewElapsed: elapsed).frame(width: 38, height: 28)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed, previewReducedMotion: true)
                            .scaleEffect(14.0 / 16).frame(width: 38, height: 28)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(2).frame(width: 38, height: 28)
                    }
                }
            }.padding(18).frame(width: 430, height: 310).background(.black).preferredColorScheme(.dark)
        }
        let host = NSHostingView(rootView: board(0))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 310), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        settle()
        let url = output.appendingPathComponent("Task-status-motion.gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 270, nil) else { fatalError("Cannot create task motion preview") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<270 {
            // Render the entire SwiftUI tree, independent of AppKit's cached dirty layers.
            let renderer = ImageRenderer(content: board(Double(frame) / 15).environment(\.colorScheme, .dark))
            renderer.scale = 1
            guard let cgImage = renderer.cgImage else { fatalError("Could not render task frame") }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            CGImageDestinationAddImage(destination, bitmap.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
            if [0, 3, 6, 9, 18, 36].contains(frame) {
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Task-status-frame-\(frame).png"))
            }
        }
        verifyPresentation(CGImageDestinationFinalize(destination), "Failed to save task motion preview")
        print("Rendered production task glyphs at widget, minimal and six-point list sizes, including reduced motion")
    }

    @MainActor private static func captureTaskPanel(output: URL, fixtures: [AgentSession]) throws {
        let store = AgentActivityStore.shared
        store.configurePreview(fixtures); store.expandedTaskID = nil
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
            verifyPresentation(vm.notchSize.height == initialHeight && window.frame.height == windowSize.height,
                               "Task filtering or inline details changed the fixed panel height")
        }
        try snapshot("Task-panel-compact")
        let originalIDs = store.notchSessions.map(\.identity)
        store.markAllRead()
        try snapshot("Task-panel-all-read")
        verifyPresentation(store.unread.isEmpty && store.notchSessions.map(\.identity) == originalIDs,
                           "Bulk read removed or reordered notch rows")
        store.configurePreview(fixtures); store.retainNotchOrder()
        let unread = store.unread.count
        store.selectNotchFilter(.all)
        try snapshot("Task-panel-all")
        verifyPresentation(vm.notchSize.height == initialHeight, "All resized the fixed panel")
        verifyPresentation(store.unread.count == unread, "Selecting All marked unseen tasks read")
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        verifyPresentation(scrolls.contains { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height }, "All tasks are not scrollable")
        store.showDetails(fixtures[0])
        try snapshot("Task-panel-inline")
        verifyPresentation(store.expandedTaskID == fixtures[0].identity, "Details did not expand inline")
        store.toggleInlineDetails(fixtures[1])
        try snapshot("Task-panel-second-inline")
        verifyPresentation(store.expandedTaskID == fixtures[1].identity, "Only one inline row should be expanded")
        var longTask = fixtures[1]
        longTask.userPrompt = String(repeating: AgentText.t("检查多个项目的任务状态和界面对齐。", "Check concurrent project task states and alignment. "), count: 12)
        longTask.activityDetail = "exec_command\n" + String(repeating: "swift test --parallel\n", count: 5)
        store.configurePreview([longTask] + fixtures.filter { $0.identity != longTask.identity })
        try snapshot("Task-panel-long-text")
        // Reading does not remove history; the chosen time window controls retention.
        if let finished = store.visible.first(where: { !$0.state.isActive }) {
            store.markRead(finished, keepVisible: true)
            verifyPresentation(store.visible.contains { $0.identity == finished.identity }, "Reading removed the row mid-browse")
            store.finishReading()
            verifyPresentation(store.visible.contains { $0.identity == finished.identity }, "Reading removed recent task history")
        }
        if var historical = fixtures.first(where: { !$0.state.isActive }) {
            let previousWindow = store.historyWindow
            historical.updatedAt = store.now.addingTimeInterval(-3 * 3600)
            store.configurePreview([historical]); store.markRead(historical)
            store.historyWindow = .oneHour
            verifyPresentation(store.visible.isEmpty, "One-hour history included an older finished task")
            store.historyWindow = .fiveHours
            verifyPresentation(store.visible.count == 1, "Five-hour history omitted a read three-hour-old task")
            store.historyWindow = previousWindow
        }
        var unreadResult = fixtures[5]
        unreadResult.title = AgentText.t("修复任务筛选", "Fix task filtering")
        unreadResult.updatedAt = store.now.addingTimeInterval(-120)
        var readResult = unreadResult
        readResult.id = "33333333-3333-4333-8333-333333333333"
        readResult.title = AgentText.t("核对英文布局", "Review English layout")
        readResult.updatedAt = store.now.addingTimeInterval(-720)
        store.configurePreview([unreadResult, readResult]); store.expandedTaskID = nil
        store.markRead(readResult); store.retainNotchOrder()
        try snapshot("Task-panel-read-history")
        verifyPresentation(store.visible.count == 2 && store.unread.count == 1, "Read history styling changed record retention")
        store.configurePreview(fixtures); store.retainNotchOrder()
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
        store.configurePreview(fixtures); store.expandedTaskID = nil
    }

    @MainActor private static func verifyCatRubRegion() throws {
        var calls: [CatSide] = []
        let director = NotchCatDirector()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayUUID
        let open = CatWingSpace(occupied: 20, limit: 46, height: 32)
        var playback = Task { await director.run(spaces: [.left: open, .right: open], screen: screen, previewPlayback: true) }
        defer { playback.cancel(); director.stop() }
        let host = NSHostingView(rootView: CatEdgeRubRegion(enabled: true,
            hover: { director.edgePointer($0) },
            summon: { calls.append($0); director.summon($0) },
            cancel: { director.cancelSummon() }).frame(width: 200, height: 32))
        let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 200, height: 32),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        settle(); host.layoutSubtreeIfNeeded()
        let region = descendants(host).compactMap { $0 as? CatEdgeRubRegion.Region }.first!
        let rect = region.shellFrame
        var pointer = CGPoint(x: rect.midX, y: rect.midY)
        var buttons = 0
        var time = 0.0
        region.pointerLocation = { pointer }; region.pressedButtons = { buttons }; region.clock = { time }
        director.pointer(true) // Production shell-hover gate must permit an accepted edge summon.
        func rub(_ side: CatSide, at start: Double) {
            let xs: [CGFloat] = side == .left ? [-5, -15, -2, -15] : [205, 215, 202, 215]
            for (i, x) in xs.enumerated() {
                pointer = CGPoint(x: rect.minX + x, y: rect.midY); time = start + Double(i) * 0.2
                settle() // The production Timer samples input; no direct call into recognition.
            }
        }
        func sampleFor(_ duration: TimeInterval, _ check: () -> Void = {}) {
            let end = Date().addingTimeInterval(duration)
            while Date() < end {
                RunLoop.main.run(until: Date().addingTimeInterval(0.015))
                check()
            }
        }
        func waitForVisible(_ side: CatSide, crowded: Bool = false) {
            let deadline = Date().addingTimeInterval(1.25)
            func visible() -> Bool {
                director.pose.active && !director.pose.concealed && director.pose.side == side
                    && director.pose.reservedWidth >= 4 && director.pose.crowded == crowded
            }
            while !visible() && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.015))
            }
            verifyPresentation(visible(), "No visible cat after accepted gesture: side=\(side), crowded=\(crowded), pose=\(director.pose)")
        }
        rub(.left, at: 0)
        verifyPresentation(calls == [.left], "Pointer sampling did not recognize left rub")
        waitForVisible(.left)
        func verifyRetreat(_ message: String, trigger: () -> Void) {
            let initial = director.pose.reservedWidth
            verifyPresentation(initial > 0, "Retreat test had no visible starting pose: " + message)
            // Observe the actual published frames synchronously. Polling timestamps
            // include an unrelated run-loop delay and cannot measure frame velocity.
            var frames: [(time: TimeInterval, width: CGFloat)] = []
            let observation = director.$pose.sink { pose in
                frames.append((ProcessInfo.processInfo.systemUptime, pose.reservedWidth))
            }
            trigger()
            verifyPresentation(director.pose.reservedWidth == initial, "Trigger instantly cleared geometry: " + message)
            sampleFor(0.65)
            observation.cancel()
            let intermediate = frames.contains { $0.width > 0 && $0.width < initial }
            for (before, after) in zip(frames, frames.dropFirst()) {
                verifyPresentation(after.width <= before.width, "Retreat reversed direction: " + message)
                // Maximum smoothstep velocity is 1.5 / 0.25 seconds, plus rounding.
                verifyPresentation(before.width - after.width <= initial * 6 * (after.time - before.time) + 1.1,
                    "Retreat exceeded its velocity: \(message), frames=\(frames)")
            }
            verifyPresentation(intermediate && !director.pose.active && director.pose.reservedWidth == 0,
                "Retreat did not finish continuously: \(message), initial=\(initial), final=\(director.pose.reservedWidth), active=\(director.pose.active), intermediate=\(intermediate)")
        }
        // Start the continuity check after entry, not on its first quantized pixel.
        sampleFor(0.9)
        verifyRetreat("held mouse button") { buttons = 1; director.cancelSummon() }
        verifyPresentation(region.hitTest(.zero) == nil, "Cat region intercepted a widget click")
        buttons = 0; rub(.right, at: 4)
        verifyPresentation(calls == [.left, .right], "Pointer sampling did not recognize right rub")
        waitForVisible(.right)
        // Staying over the shell, leaving/re-entering an edge and repeated requests
        // must not hide, reset or indefinitely extend a committed interaction.
        director.edgePointer(nil); director.edgePointer(.left)
        director.summon(.left)
        verifyPresentation(director.pose.side == .right && !director.pose.concealed, "A repeated gesture moved or hid the cat")
        sampleFor(7) {
            verifyPresentation(!director.pose.active || director.pose.side == .right, "A repeated gesture was queued for the opposite side")
        }
        verifyPresentation(!director.pose.active && director.pose.reservedWidth == 0, "Hover held the cat spacer open after natural completion")
        director.summon(.right); waitForVisible(.right)
        verifyRetreat("physical notch hover") { director.pointer(true, source: "camera") }
        director.pointer(false, source: "camera")
        director.summon(.left); waitForVisible(.left)
        verifyRetreat("layout capacity changed") { director.updateSpaces([.left: CatWingSpace(occupied: 21, limit: 46, height: 32), .right: open]) }
        playback.cancel(); director.stop(); settle()
        let full = CatWingSpace(occupied: 46, limit: 46, height: 32)
        playback = Task { await director.run(spaces: [.left: open, .right: full], screen: screen, previewPlayback: true) }
        settle(); rub(.right, at: 8)
        verifyPresentation(calls == [.left, .right, .right], "A full right wing did not recognize its gesture")
        waitForVisible(.right, crowded: true)
        sampleFor(3.5) {
            verifyPresentation(director.pose.reservedWidth <= 8, "Crowded peek exceeded its eight-point budget")
            verifyPresentation(!director.pose.active || director.pose.side == .right, "Crowded peek swapped sides")
        }
        verifyPresentation(!director.pose.active, "Crowded peek did not withdraw while hovered")
        director.updateSpaces([.left: full, .right: full])
        director.summon(.left); waitForVisible(.left, crowded: true)
        verifyPresentation(director.pose.active && director.pose.side == .left && director.pose.crowded, "Both full wings discarded the requested left peek")
        verifyRetreat("crowded cancellation") { director.cancelSummon() }
        director.summon(.right); director.cancelSummon()
        sampleFor(0.4)
        verifyPresentation(!director.pose.active, "Cancelled pending summon still appeared")
        director.summon(.left); waitForVisible(.left, crowded: true)
        verifyPresentation(director.pose.active && director.pose.side == .left, "Pending cancellation blocked the next gesture")
        verifyRetreat("next gesture after pending cancellation") { director.cancelSummon() }
        region.enabled = false; region.refreshSampling(); region.clear()
        playback.cancel(); director.stop()
        window.orderOut(nil); window.contentView = nil; window.close()
        print("Verified production pointer timer -> recognizer -> director -> visible pose; left/right, natural completion while hovered, repeated gestures, continuous cancellation, layout changes and same-side crowded peeks (simulated pointer input)")
    }

    @MainActor private static func captureCat(output: URL, fixtures: [AgentSession]) throws {
        UserDefaults.standard.set(true, forKey: "notchCatEnabled")
        let vm = BoringViewModel()
        vm.hideOnClosed = false
        let coordinator = BoringViewCoordinator.shared
        coordinator.helloAnimationRunning = false
        coordinator.musicLiveActivityEnabled = true
        coordinator.expandingView.show = false
        coordinator.sneakPeek.show = false
        let activity = AgentActivityStore.shared
        let quota = QuotaNotchStore.shared
        let music = MusicManager.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var records: [[String: Any]] = []
        for mask in 0..<8 {
            quota.configureSettingsPreview(paused: mask & 1 == 0)
            music.isPlaying = mask & 2 != 0; music.isPlayerIdle = !music.isPlaying
            activity.configurePreview(mask & 4 != 0 ? fixtures : [])
            activity.compactExpanded = false
            for height: CGFloat in [24, 32, 38] {
                vm.close(); vm.closedNotchSize.height = height; vm.hideOnClosed = false
                for side in CatSide.allCases {
                    var baseline: (Int, Int)?
                    var baselineCream = 0
                    for active in [false, true] {
                        let crowded = side == .right && (mask == 7 || mask == 4)
                        let pose = CatPose(side: side, action: .curious, elapsed: 2, active: active,
                                           frame: crowded ? "Cat-cheek-rub-2" : nil, width: crowded ? 8 : nil, crowded: crowded)
                        let host = NSHostingView(rootView: ContentView(catPreviewPose: pose).environmentObject(vm)
                            .transaction { $0.animation = nil; $0.disablesAnimations = true }
                            .background(Color(red: 0.25, green: 0.15, blue: 0.35)))
                        window.contentView = host; window.setContentSize(windowSize); window.orderFront(nil)
                        settle(); host.layoutSubtreeIfNeeded(); settle()
                        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
                        let row = Int(3 * scale)
                        let pixels = (0..<bitmap.pixelsWide).filter { x in
                            let c = bitmap.colorAt(x: x, y: row)!.usingColorSpace(.deviceRGB)!
                            return max(c.redComponent, max(c.greenComponent, c.blueComponent)) < 0.06
                        }
                        let edges = (pixels.first!, pixels.last!)
                        // A stable shell alone does not prove the crowded cat was drawn.
                        // Count its warm cream pixels, excluding white text and state colors.
                        var cream = 0
                        if crowded {
                            for y in 0..<min(bitmap.pixelsHigh, Int(height * scale)) {
                                for x in 0..<bitmap.pixelsWide {
                                    let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                                    if c.redComponent > 0.85 && c.greenComponent > 0.8 && c.blueComponent > 0.45
                                        && c.greenComponent - c.blueComponent > 0.04
                                        && c.redComponent - c.greenComponent < 0.15 { cream += 1 }
                                }
                            }
                        }
                        // Save evidence before checking: failures must still provide a screenshot.
                        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Cat-check-\(mask)-\(Int(height))-\(side.rawValue)-\(active).png"))
                        verifyPresentation(vm.effectiveClosedNotchHeight == height, "Cat fixture height was reset")
                        if let baseline {
                            let change = side == .left ? baseline.0 - edges.0 : edges.1 - baseline.1
                            let stationary = side == .left ? abs(edges.1 - baseline.1) : abs(edges.0 - baseline.0)
                            verifyPresentation(stationary <= 2, "Cat moved the opposite wing: mask \(mask), \(side), height \(height)")
                            verifyPresentation(change >= -2 && CGFloat(change) <= 32 * scale + 2, "Cat exceeded wing budget")
                            let full = side == .right && (mask == 7 || mask == 4)
                            if full { verifyPresentation(cream > baselineCream + 2, "Crowded cat missing from rendered pixels: mask \(mask), height \(height), baseline=\(baselineCream), active=\(cream)") }
                            verifyPresentation(full ? abs(change) <= 2 : change > 0, "Wrong cat availability: mask \(mask), \(side), height \(height), delta \(change)")
                            records.append(["modules": mask, "height": height, "side": side.rawValue, "addedPixels": change])
                        } else { baseline = edges; baselineCream = cream }
                        if active && height == 32 {
                            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Cat-layout-\(mask)-\(side.rawValue).png"))
                        }
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted]).write(to: output.appendingPathComponent("Cat-layout-audit.json"))
        try capture(VStack(spacing: 22) {
            ForEach(CatAction.allCases, id: \.rawValue) { action in
                HStack(spacing: 14) {
                    Text(action.rawValue).font(.caption).frame(width: 70, alignment: .leading)
                    ForEach([0.3, 0.9, 1.6, 3.2, 4.0, 7.5, 8.5], id: \.self) { elapsed in
                        VStack {
                            NotchCatDrawing(pose: CatPose(action: action, elapsed: elapsed, active: true), empty: action == .rest)
                                .frame(width: 64, height: 52).clipped().background(.black)
                            Text(String(format: "%.1fs", elapsed)).font(.caption2)
                        }
                    }
                }
            }
        }.padding(20).background(.black).foregroundStyle(.white), width: 690, name: "Cat-storyboard", output: output, height: 380)
        window.orderOut(nil); window.contentView = nil; window.close(); vm.destroy()
        quota.configureSettingsPreview(paused: false); activity.configurePreview(fixtures)
        music.isPlaying = false; music.isPlayerIdle = true
        print("Verified \(records.count) cat layouts with physical-notch anchoring")
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
