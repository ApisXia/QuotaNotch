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
        try BubbleShelfVerification.run()
        try BubbleCollectorVerification.run()
        BubbleShelfStore.shared.resetPreviewConfiguration()
        let shelfPreviewFile = output.appendingPathComponent("shelf-preview.txt")
        let shelfPreviewNote = output.appendingPathComponent("shelf-preview-note.md")
        try Data(AgentText.t("内置预览文件\n用于收纳面板截图", "Built-in preview file\nfor Shelf panel screenshots").utf8).write(to: shelfPreviewFile)
        try Data("# Preview note\n\nA second built-in document for the shelf fixture.".utf8).write(to: shelfPreviewNote)
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
            for page in ["General", "Quota", "Activity", "Media", "Calendar", "Appearance", "System", "Shelf", "About"] {
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
        try captureBubbleShelfPreview(output: output)
        try captureBubbleShelfOpenLayouts(output: output)
        try captureBubbleCollectorMotion(output: output)
        try captureBubbleClosedLayouts(output: output, fixtures: fixtures)
        try captureBubbleShelfAudioLayouts(output: output, fixtures: fixtures)
        try captureBubbleShelfGestureRouting(output: output)
        try captureBubbleGlyphOrbit(output: output)
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
        var renderedFrames: [String: CGRect] = [:]
        let savedComfortable = UserDefaults.standard.bool(forKey: "quotaComfortable")
        UserDefaults.standard.set(false, forKey: "quotaComfortable")
        defer { UserDefaults.standard.set(savedComfortable, forKey: "quotaComfortable") }
        var modeAudit: [[String: Any]] = []
        let host = NSHostingView(rootView: ContentView().environmentObject(vm)
            .onPreferenceChange(NotchModuleAuditKey.self) { renderedModules = $0 }
            .onPreferenceChange(NotchModuleFrameAuditKey.self) { renderedFrames = $0 }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background(Color(red: 0.25, green: 0.15, blue: 0.35)))
        func verifyGeometry(_ label: String, widget: CGFloat) {
            guard let camera = renderedFrames["camera"] else { fatalError("Missing camera geometry in \(label)") }
            verifyPresentation(abs(camera.midX - host.bounds.midX) <= 1, "Physical notch shifted in \(label): \(camera)")
            if let album = renderedFrames["album"] {
                verifyPresentation(abs(album.width - widget) <= 1, "Album stretched in \(label): \(album)")
                verifyPresentation(abs(album.maxX + QuotaCompactMetrics.spacing - camera.minX) <= 1,
                    "Album moved away from physical notch in \(label): \(album), camera \(camera)")
            }
            for name in ["quota", "task"] {
                if let mode = renderedModules[name], let frame = renderedFrames[name] {
                    let expected = mode == "minimal" ? CGFloat(16) : widget
                    verifyPresentation(abs(frame.width - expected) <= 1, "\(name) width changed in \(label): \(frame.width) vs \(expected)")
                    verifyPresentation(frame.maxX <= camera.minX + 1 || frame.minX >= camera.maxX - 1,
                        "\(name) overlaps physical notch in \(label)")
                }
            }
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(windowSize)
        window.orderFront(nil)
        vm.open()
        for headerHeight: CGFloat in [24, 32, 38] {
            vm.closedNotchSize.height = headerHeight
            for (index, tab) in [NotchViews.home, .activity, .aiUsage, .bubbleShelf].enumerated() {
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
        verifyPresentation(coordinator.currentView == .bubbleShelf && !AgentActivityStore.shared.notchReadEnabled,
                           "Swiping to Shelf did not select the Shelf tab")
        swipe.handleScroll(x: -20, y: 0, at: 7, phase: .began, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .bubbleShelf, "Swiping at the last tab wrapped around")
        swipe.handleScroll(x: 20, y: 0, at: 8, phase: .began, eventWindow: window, location: inside)
        verifyPresentation(coordinator.currentView == .activity && AgentActivityStore.shared.notchReadEnabled,
                           "Swiping back did not leave Shelf correctly")
        swipe.handleScroll(x: 20, y: 0, at: 9, phase: .began, eventWindow: window, location: inside)
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
        var combinedEdges: [String: (Int, Int)] = [:]
        func blackEdges(_ bitmap: NSBitmapImageRep) -> (Int, Int) {
            let row = max(1, Int(5 * CGFloat(bitmap.pixelsHigh) / host.bounds.height))
            let points = (0..<bitmap.pixelsWide).filter { x in
                guard let c = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                return max(c.redComponent, max(c.greenComponent, c.blueComponent)) < 0.06
            }
            return (points.first ?? 0, points.last ?? 0)
        }
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
                verifyGeometry("\(layout)-\(headerHeight)-\(expanded)", widget: QuotaCompactMetrics.iconSize(height: headerHeight))
                modeAudit.append(["case": layout, "height": headerHeight, "taskSelected": expanded, "rendered": renderedModules])
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Notch-closed-\(Int(headerHeight))-\(expanded)\(suffix).png"))
                let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2)!.usingColorSpace(.deviceRGB)!
                precondition(max(color.redComponent, max(color.greenComponent, color.blueComponent)) < 0.06, "Closed notch detached")
                if layout == "combined" {
                    combinedEdges["\(Int(headerHeight))-\(expanded)"] = blackEdges(bitmap)
                }
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
                let baseEdges = blackEdges(baseline)
                for selection in [false, true] {
                    let edges = combinedEdges["\(Int(headerHeight))-\(selection)"]!
                    verifyPresentation(abs(edges.0 - baseEdges.0) <= 1,
                        "Adding minimal moved the music-side edge at height \(headerHeight): \(edges.0) vs \(baseEdges.0)")
                    verifyPresentation(abs(CGFloat(edges.1 - baseEdges.1) - budget * scale) <= 2,
                        "Minimal did not expand only the right side at height \(headerHeight)")
                }
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
                    verifyGeometry("\(playback)-\(headerHeight)-\(expanded)", widget: QuotaCompactMetrics.iconSize(height: headerHeight))
                    modeAudit.append(["case": playback, "height": headerHeight, "taskSelected": expanded, "rendered": renderedModules])
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Notch-transition-\(Int(headerHeight))-\(expanded)-\(playback).png"))
                }
            }
        }
        for comfortable in [true, false] {
            UserDefaults.standard.set(comfortable, forKey: "quotaComfortable")
            for headerHeight: CGFloat in [24, 32, 38] {
                vm.closedNotchSize.height = headerHeight
                for scenario in cases.reversed() {
                    QuotaNotchStore.shared.configureSettingsPreview(paused: !scenario.quota)
                    MusicManager.shared.isPlaying = scenario.music
                    MusicManager.shared.isPlayerIdle = !scenario.music
                    activity.configurePreview(scenario.tasks ? fixtures : [])
                    for expanded in [true, false] {
                        activity.compactExpanded = expanded
                        settle(); host.layoutSubtreeIfNeeded()
                        let widget = QuotaCompactMetrics.iconSize(height: headerHeight, comfortable: scenario.quota && comfortable)
                        verifyGeometry("reverse-\(scenario.name)-\(headerHeight)-\(expanded)-comfortable=\(comfortable)", widget: widget)
                        modeAudit.append(["case": "reverse-" + scenario.name, "height": headerHeight,
                                          "taskSelected": expanded, "comfortable": comfortable, "rendered": renderedModules])
                    }
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

    /// Render the shelf tab and the closed glyph at its actual widget/minimal footprints.
    /// The fixture uses ordinary text, URL, and file items; it never reads the user's shelf.
    @MainActor private static func captureBubbleShelfPreview(output: URL) throws {
        let shelf = BubbleShelfStore.shared
        let shelfPreviewFile = output.appendingPathComponent("shelf-preview.txt")
        let shelfPreviewNote = output.appendingPathComponent("shelf-preview-note.md")
        shelf.configurePreview(items: [
            BubbleShelfItem(kind: .file, title: "shelf-preview.txt", resourceURL: shelfPreviewFile),
            BubbleShelfItem(kind: .text, title: AgentText.t("选中的文本", "Selected text"), text: AgentText.t("一段可拖出的示例文本", "A sample text item that can be dragged out")),
            BubbleShelfItem(kind: .url, title: "example.com", resourceURL: URL(string: "https://example.com/preview")!),
            BubbleShelfItem(kind: .file, title: "shelf-preview-note.md", resourceURL: shelfPreviewNote)
        ])
        shelf.isReceiving = false
        let originalReceiving = shelf.isReceiving
        defer {
            shelf.isReceiving = originalReceiving
            shelf.resetPreviewConfiguration()
        }

        for receiving in [false, true] {
            shelf.isReceiving = receiving
            try capture(BubbleShelfView().background(Color.black).preferredColorScheme(.dark), width: 520,
                        name: "Shelf-panel-\(receiving ? "receiving" : "paused")", output: output, height: 420)
            try capture(BubbleShelfSettingsView().background(Color.black).preferredColorScheme(.dark), width: 520,
                        name: "Shelf-settings-\(receiving ? "receiving" : "paused")", output: output, height: 260)
        }

        for receivingState in [false, true] {
            let compactHost = HStack(alignment: .center, spacing: 28) {
                ForEach([24, 32, 38], id: \.self) { rawHeight in
                    let height = CGFloat(rawHeight)
                    VStack(spacing: 5) {
                        Text("\(rawHeight)pt").font(.system(size: 9)).foregroundStyle(.secondary)
                        HStack(spacing: 9) {
                            BubbleShelfClosedControl(
                                state: BubbleShelfCompactState(itemCount: 3, isReceiving: receivingState,
                                                               onOpen: {}, onVerticalSwipe: { _ in }, writers: { [] }),
                                presentation: .widget, height: height, widgetWidth: QuotaCompactMetrics.iconSize(height: height)
                            )
                            BubbleShelfCompanion(
                                state: BubbleShelfCompactState(itemCount: 3, isReceiving: receivingState,
                                                               onOpen: {}, onVerticalSwipe: { _ in }, writers: { [] }),
                                height: height, widgetWidth: QuotaCompactMetrics.iconSize(height: height)
                            )
                        }
                    }
                }
            }
            try capture(compactHost.background(Color.black).preferredColorScheme(.dark), width: 420,
                        name: "Shelf-closed-\(receivingState ? "receiving" : "paused")", output: output, height: 92)
        }
        for count in 0...4 {
            let payloads = Array(shelf.items.prefix(count)).map(BubbleCollectorPayload.stored)
            try capture(BubbleCollectorFixtureView(payloads: payloads)
                .background(Color.black).preferredColorScheme(.dark), width: 220,
                name: "Shelf-collector-count-\(count)", output: output, height: 190)
        }
    }

    /// Render Shelf through the production ContentView at the real 640×190 open-notch size.
    /// The standalone panel previews are intentionally larger; these fixtures catch title,
    /// status, list and error rows overflowing the actual notch body.
    @MainActor private static func captureBubbleShelfOpenLayouts(output: URL) throws {
        let shelf = BubbleShelfStore.shared
        let fixtureURL = output.appendingPathComponent("shelf-open-fixture.txt")
        try Data("Shelf open-notch fixture".utf8).write(to: fixtureURL)
        let noteURL = output.appendingPathComponent("shelf-open-note.md")
        try Data("# Shelf open-notch fixture\n\nA second compact row.".utf8).write(to: noteURL)

        let vm = BoringViewModel()
        vm.hideOnClosed = false
        let coordinator = BoringViewCoordinator.shared
        coordinator.helloAnimationRunning = false
        coordinator.currentView = .bubbleShelf
        QuotaNotchStore.shared.menuOpen = true
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView().environmentObject(vm)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background(Color(red: 0.25, green: 0.15, blue: 0.35)))
        window.contentView = host
        window.orderFront(nil)
        vm.open()

        let baseItems: [BubbleShelfItem] = [
            BubbleShelfItem(kind: .file, title: "shelf-open-fixture.txt", resourceURL: fixtureURL),
            BubbleShelfItem(kind: .text, title: AgentText.t("选中的文本", "Selected text"),
                            text: AgentText.t("一段可拖出的示例文本", "A sample text item that can be dragged out")),
            BubbleShelfItem(kind: .url, title: "example.com", resourceURL: URL(string: "https://example.com/preview")!),
            BubbleShelfItem(kind: .file, title: "shelf-open-note.md", resourceURL: noteURL)
        ]
        let scenarios: [(name: String, items: [BubbleShelfItem], receiving: Bool, result: BubbleShelfImportResult?)] = [
            ("empty-paused", [], false, nil),
            ("populated-receiving", baseItems, true, nil),
            ("long-error", baseItems.enumerated().map { index, item in
                var copy = item
                copy.title = index == 0
                    ? AgentText.t("一个很长的文件标题用于验证英文和中文收纳布局不会溢出", "A deliberately long file title checks that Shelf rows stay inside the open notch")
                    : item.title
                return copy
            }, false, BubbleShelfImportResult(skippedCount: 1, errors: ["The shelf could not be saved."]))
        ]
        defer {
            shelf.resetPreviewConfiguration()
            QuotaNotchStore.shared.menuOpen = false
            window.orderOut(nil); window.contentView = nil; window.close(); vm.destroy()
        }

        for scenario in scenarios {
            shelf.configurePreview(items: scenario.items)
            shelf.isReceiving = scenario.receiving
            if let result = scenario.result { shelf.recordImportResult(result) }
            settle(); host.layoutSubtreeIfNeeded(); settle()
            verifyPresentation(vm.notchSize == openNotchSize,
                               "Shelf open fixture changed the fixed notch size in \(scenario.name): \(vm.notchSize)")
            let scroll = descendants(host).compactMap { $0 as? NSScrollView }.max { $0.frame.width < $1.frame.width }
            if scenario.items.isEmpty {
                verifyPresentation(scroll == nil || (scroll?.frame.height ?? 0) <= 1,
                                   "Empty Shelf unexpectedly reserved a large list scroll region")
            } else {
                guard let scroll, let document = scroll.documentView else {
                    fatalError("Populated Shelf has no scrollable list in \(scenario.name)")
                }
                verifyPresentation(scroll.frame.minY >= -1 && scroll.frame.maxY <= host.bounds.height + 1,
                                   "Shelf list escaped the open-notch bounds in \(scenario.name): \(scroll.frame)")
                verifyPresentation(document.bounds.height >= scroll.contentView.bounds.height - 1,
                                   "Shelf list content was not available to scroll in \(scenario.name)")
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Missing open Shelf bitmap for \(scenario.name)")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(
                "Notch-shelf-open-\(scenario.name).png"))
        }
    }

    /// Capture the real floating collector panel so the cloud artifact includes the
    /// gather/hold/collapse cycle, plus a small pointer-light storyboard from the same
    /// native SwiftUI/Metal view. No Accessibility or external selection is involved.
    @MainActor private static func captureBubbleCollectorMotion(output: URL) throws {
        let shelf = BubbleShelfStore.shared
        let fileURL = output.appendingPathComponent("collector-motion-fixture.txt")
        try Data("Collector motion fixture".utf8).write(to: fileURL)
        let noteURL = output.appendingPathComponent("collector-motion-note.md")
        try Data("# Collector motion fixture\n\nA second native card.".utf8).write(to: noteURL)
        let fixtureDate = Date()
        let fixtureItems: [BubbleShelfItem] = [
            BubbleShelfItem(kind: .file, title: "collector-motion-fixture.txt", addedAt: fixtureDate, resourceURL: fileURL),
            BubbleShelfItem(kind: .text, title: AgentText.t("示例文本", "Sample text"), addedAt: fixtureDate.addingTimeInterval(1), text: "Collector motion sample"),
            BubbleShelfItem(kind: .url, title: "example.com", addedAt: fixtureDate.addingTimeInterval(2), resourceURL: URL(string: "https://example.com/collector")!),
            BubbleShelfItem(kind: .file, title: "collector-motion-note.md", addedAt: fixtureDate.addingTimeInterval(3), resourceURL: noteURL)
        ]
        let finalURL = output.appendingPathComponent("collector-motion-final.txt")
        try Data("The final inserted item.".utf8).write(to: finalURL)
        let finalItem = BubbleShelfItem(kind: .file, title: "collector-motion-final.txt", resourceURL: finalURL)
        let payloads = fixtureItems.map(BubbleCollectorPayload.stored)
        let finalPayload = BubbleCollectorPayload.stored(finalItem)
        let controller = BubbleCollectorController.shared
        let anchor = CGPoint(x: 320, y: 320)
        shelf.resetPreviewConfiguration()
        shelf.isReceiving = true
        // Keep one selection presentation and one panel alive while the shelf
        // itself grows. The selection payload is a distinct fifth item; it is
        // committed only for the final gather/hold/collapse proof.
        controller.showSelectionForTesting(contents: [finalPayload], anchor: anchor)
        defer {
            controller.hidePreviewForTesting()
            shelf.resetPreviewConfiguration()
        }

        guard let panel = NSApp.windows.compactMap({ $0 as? NSPanel }).first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("bubble-collector-preview-panel")
        }), let content = panel.contentView else {
            fatalError("Collector motion panel was not created")
        }
        content.layoutSubtreeIfNeeded()
        // Capture timed frames first and encode the GIF afterward. GIF encoding and
        // thumbnail work can take longer than one frame interval and would otherwise
        // let the live 2.05s gather/hold/collapse animation expire between snapshots.
        var motionFrames: [CGImage] = []
        let captureStart = Date()
        var candidateCaptureStart: Date?
        var observedCollapsedEnd = false
        for frameIndex in 0..<81 {
            let stageIndex = min(fixtureItems.count, frameIndex / 14)
            if frameIndex <= 56 && frameIndex % 14 == 0 {
                // Keep one panel/TimelineView alive while the stable artwork IDs
                // reflow through 0→1→2→3→4. This is an insertion sequence, not
                // five independently recreated fixture scenes.
                shelf.configurePreview(items: Array(fixtureItems.prefix(stageIndex)))
            }
            if frameIndex == 56 {
                // Refresh the injected candidate immediately before capture so a
                // slow CI render cannot cross its 18s fixture expiration. Reusing
                // the existing panel keeps this a real insertion, not a new scene.
                controller.showSelectionForTesting(contents: [finalPayload], anchor: anchor)
                controller.captureCurrentCandidate()
                guard shelf.items.count == 5,
                      case .captured(let captured, _, _, _) = controller.presentation,
                      captured.count == 4 else {
                    fatalError("Collector candidate capture did not produce the fifth shelf item")
                }
                candidateCaptureStart = Date()
            }
            let frameDeadline = captureStart.addingTimeInterval(Double(frameIndex + 1) / 12.0)
            while Date() < frameDeadline {
                RunLoop.main.run(mode: .default,
                                 before: min(frameDeadline, Date().addingTimeInterval(0.01)))
            }
            // The panel may replace its hosting view during a real capture. Always
            // cache the current view instead of retaining a detached NSHostingView.
            guard let liveContent = panel.contentView else {
                let elapsed = candidateCaptureStart.map { Date().timeIntervalSince($0) } ?? 0
                guard candidateCaptureStart != nil, elapsed >= BubbleCollectorMotion.totalDuration else {
                    fatalError("Collector motion panel lost its content view at frame \(frameIndex)")
                }
                // The scheduled expiration is the real collapsed endpoint. Keep
                // the movie's timing grid intact with transparent frames after
                // the native panel has correctly disappeared.
                let collapsed = clearCollectorFrame(width: Int(BubbleCollectorFloatingPanel.size.width),
                                                     height: Int(BubbleCollectorFloatingPanel.size.height))
                motionFrames.append(collapsed)
                observedCollapsedEnd = true
                if [0, 14, 28, 42, 56, 70, 80].contains(frameIndex) {
                    try NSBitmapImageRep(cgImage: collapsed).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(
                        "Bubble-collector-insertion-frame-\(frameIndex).png"))
                }
                continue
            }
            liveContent.layoutSubtreeIfNeeded()
            guard let bitmap = liveContent.bitmapImageRepForCachingDisplay(in: liveContent.bounds) else {
                fatalError("Missing collector motion frame \(frameIndex)")
            }
            liveContent.cacheDisplay(in: liveContent.bounds, to: bitmap)
            guard let cgImage = bitmap.cgImage else {
                fatalError("Missing collector motion image \(frameIndex)")
            }
            motionFrames.append(cgImage)
            if [0, 14, 28, 42, 56, 70, 80].contains(frameIndex) {
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(
                    "Bubble-collector-insertion-frame-\(frameIndex).png"))
            }
        }
        if !observedCollapsedEnd, let candidateCaptureStart {
            let expirationDeadline = Date().addingTimeInterval(0.35)
            while controller.presentation != nil && Date() < expirationDeadline {
                RunLoop.main.run(mode: .default,
                                 before: min(expirationDeadline, Date().addingTimeInterval(0.01)))
            }
            observedCollapsedEnd = controller.presentation == nil
                && Date().timeIntervalSince(candidateCaptureStart) >= BubbleCollectorMotion.totalDuration
        }
        guard shelf.items.count == 5,
              candidateCaptureStart != nil,
              observedCollapsedEnd,
              motionFrames.count == 81,
              controller.presentation == nil else {
            fatalError("Collector motion capture lost its final captured presentation")
        }
        let movieURL = output.appendingPathComponent("Bubble-collector-insertion.gif")
        guard let destination = CGImageDestinationCreateWithURL(movieURL as CFURL,
                                                                  UTType.gif.identifier as CFString,
                                                                  motionFrames.count, nil) else {
            fatalError("Cannot create collector motion storyboard")
        }
        CGImageDestinationSetProperties(destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in motionFrames {
            CGImageDestinationAddImage(destination, frame,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12.0]] as CFDictionary)
        }
        verifyPresentation(CGImageDestinationFinalize(destination), "Failed to save collector insertion storyboard")

        controller.hidePreviewForTesting()
        for (index, pointer) in [CGPoint(x: 0.28, y: 0.36), CGPoint(x: 0.50, y: 0.28), CGPoint(x: 0.72, y: 0.62)].enumerated() {
            try capture(BubbleCollectorFixtureView(payloads: payloads, pointer: pointer)
                .background(Color.black).preferredColorScheme(.dark), width: 190,
                name: "Bubble-collector-pointer-\(index)", output: output, height: 190)
        }
    }

    private static func clearCollectorFrame(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Could not create collapsed collector frame")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("Could not finalize collapsed collector frame")
        }
        return image
    }

    /// Two native four-second receive-arc cycles at the actual widget and Minimal
    /// footprints. The same count/content state is held throughout the movie so the
    /// only moving detail is the short curved inner arc and its speed-linked glow.
    @MainActor private static func captureBubbleGlyphOrbit(output: URL) throws {
        let receivingState = BubbleShelfCompactState(itemCount: 3, isReceiving: true,
                                                     onOpen: {}, onVerticalSwipe: { _ in }, writers: { [] })
        let board = HStack(spacing: 22) {
            BubbleShelfClosedControl(state: receivingState, presentation: .widget,
                                     height: 32, widgetWidth: QuotaCompactMetrics.iconSize(height: 32))
                .frame(width: 32, height: 32)
            BubbleShelfCompanion(state: receivingState, height: 32,
                                 widgetWidth: QuotaCompactMetrics.iconSize(height: 32))
                .frame(width: 26, height: 32)
        }
        .padding(.horizontal, 22)
        .frame(width: 150, height: 76)
        .background(Color.black)
        .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: board)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 150, height: 76)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        settle(); host.layoutSubtreeIfNeeded()
        let movieURL = output.appendingPathComponent("Bubble-notch-glyph-orbit.gif")
        guard let destination = CGImageDestinationCreateWithURL(movieURL as CFURL,
                                                                  UTType.gif.identifier as CFString,
                                                                  96, nil) else {
            fatalError("Cannot create notch glyph orbit storyboard")
        }
        CGImageDestinationSetProperties(destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frameIndex in 0..<96 {
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 12.0))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Missing notch glyph orbit frame \(frameIndex)")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let cgImage = bitmap.cgImage else {
                fatalError("Missing notch glyph orbit image \(frameIndex)")
            }
            CGImageDestinationAddImage(destination, cgImage,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12.0]] as CFDictionary)
            if [0, 24, 48, 72, 95].contains(frameIndex) {
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(
                    "Bubble-notch-glyph-orbit-frame-\(frameIndex).png"))
            }
        }
        verifyPresentation(CGImageDestinationFinalize(destination), "Failed to save notch glyph orbit storyboard")
    }

    /// Check the closed physical notch with an empty configured shelf and one saved item.
    /// Existing quota, music, task, and camera footprints remain the source of truth.
    @MainActor private static func captureBubbleClosedLayouts(output: URL, fixtures: [AgentSession]) throws {
        let shelf = BubbleShelfStore.shared
        let shelfFile = output.appendingPathComponent("shelf-closed-fixture.txt")
        try Data("Closed-notch shelf fixture".utf8).write(to: shelfFile)
        let savedReceiving = shelf.isReceiving
        defer {
            shelf.isReceiving = savedReceiving
            shelf.resetPreviewConfiguration()
        }

        let vm = BoringViewModel()
        vm.hideOnClosed = false
        let coordinator = BoringViewCoordinator.shared
        coordinator.helloAnimationRunning = false
        coordinator.currentView = .home
        let quota = QuotaNotchStore.shared
        let music = MusicManager.shared
        let activity = AgentActivityStore.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close(); vm.destroy() }

        var modules: [String: String] = [:]
        var frames: [String: CGRect] = [:]
        let host = NSHostingView(rootView: ContentView().environmentObject(vm)
            .onPreferenceChange(NotchModuleAuditKey.self) { modules = $0 }
            .onPreferenceChange(NotchModuleFrameAuditKey.self) { frames = $0 }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background(Color(red: 0.25, green: 0.15, blue: 0.35)))
        window.contentView = host
        window.orderFront(nil)

        let masks = Array(0..<8)
        for itemCount in [0, 1] {
            shelf.configurePreview(items: itemCount == 0 ? [] : [
                BubbleShelfItem(kind: .file, title: "shelf-closed-fixture.txt", resourceURL: shelfFile)
            ])
            shelf.isReceiving = false
            for mask in masks {
                quota.configureSettingsPreview(paused: mask & 1 == 0)
                music.isPlaying = mask & 2 != 0
                music.isPlayerIdle = !music.isPlaying
                activity.configurePreview(mask & 4 != 0 ? fixtures : [])
                activity.compactExpanded = false
                for rawHeight: CGFloat in [24, 32, 38] {
                    vm.close()
                    vm.closedNotchSize.height = rawHeight
                    settle(); host.layoutSubtreeIfNeeded(); settle()
                    guard let camera = frames["camera"] else {
                        fatalError("Shelf closed fixture did not publish notch geometry")
                    }
                    let widget = QuotaCompactMetrics.iconSize(height: rawHeight)
                    verifyPresentation(abs(camera.midX - host.bounds.midX) <= 1,
                                       "Shelf shifted the physical notch at mask \(mask), height \(rawHeight), count \(itemCount)")
                    let hasLeftModule = (mask & 1 != 0) || (mask & 2 != 0) || (mask & 4 != 0)
                    let expectedBubble = hasLeftModule ? "minimal" : "widget"
                    verifyPresentation(modules["bubble"] == expectedBubble,
                                       "Shelf state used \(modules["bubble"] ?? "none") instead of \(expectedBubble) for mask \(mask), count \(itemCount)")
                    if let album = frames["album"], mask & 2 != 0 {
                        verifyPresentation(abs(album.width - widget) <= 1,
                                           "Shelf changed music width at mask \(mask), height \(rawHeight): \(album.width) vs \(widget)")
                    }
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(
                        "Notch-bubble-closed-mask\(mask)-height\(Int(rawHeight))-count\(itemCount).png"))
                }
            }
        }
        quota.configureSettingsPreview(paused: false)
        music.isPlaying = false; music.isPlayerIdle = true
        activity.configurePreview(fixtures)
        print("Verified closed Shelf states across \(masks.count) module masks, counts 0/1, and heights 24/32/38")
    }

    /// Capture the real closed notch for the two Shelf/audio arrangements. The
    /// pair keeps one fixed footprint while the Shelf remains the outermost
    /// left module; quota/task stay in their existing right-side positions.
    @MainActor private static func captureBubbleShelfAudioLayouts(output: URL, fixtures: [AgentSession]) throws {
        let shelf = BubbleShelfStore.shared
        let fixtureURL = output.appendingPathComponent("shelf-audio-fixture.txt")
        try Data("Shelf audio layout fixture".utf8).write(to: fixtureURL)
        let items = [BubbleShelfItem(kind: .file, title: "shelf-audio-fixture.txt", resourceURL: fixtureURL)]
        let vm = BoringViewModel()
        vm.hideOnClosed = false
        let coordinator = BoringViewCoordinator.shared
        coordinator.helloAnimationRunning = false
        coordinator.expandingView.show = false
        coordinator.sneakPeek.show = false
        coordinator.musicLiveActivityEnabled = true
        let quota = QuotaNotchStore.shared
        let music = MusicManager.shared
        let activity = AgentActivityStore.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer {
            shelf.resetPreviewConfiguration()
            quota.configureSettingsPreview(paused: false)
            music.isPlaying = false
            music.isPlayerIdle = true
            activity.configurePreview(fixtures)
            activity.compactExpanded = false
            window.orderOut(nil); window.contentView = nil; window.close(); vm.destroy()
        }

        let scenarios: [(name: String, quota: Bool, audio: Bool, tasks: Bool, receiving: Bool)] = [
            ("shelf-only-paused", false, false, false, false),
            ("audio-paused", false, true, false, false),
            ("audio-playing", false, true, false, true),
            ("quota-audio", true, true, false, true),
            ("audio-tasks", false, true, true, true),
            ("quota-audio-tasks", true, true, true, true),
            ("quota-tasks-no-audio", true, false, true, false)
        ]
        for scenario in scenarios {
            let arrangements: [BubbleShelfAudioArrangement?] = scenario.audio
                ? [.shelfMinimalAudioWidget, .shelfWidgetAudioMinimal]
                : [nil]
            for arrangement in arrangements {
                for height in [CGFloat(24), 32, 38] {
                    shelf.configurePreview(items: items)
                    shelf.isReceiving = scenario.receiving
                    quota.configureSettingsPreview(paused: !scenario.quota)
                    music.isPlaying = scenario.audio && scenario.name == "audio-playing"
                    music.isPlayerIdle = !scenario.audio || scenario.name == "audio-playing"
                    if scenario.audio && scenario.name == "audio-paused" {
                        // An idle player has no compact music module. Keep the
                        // media session active but paused for this fixture.
                        music.isPlaying = false
                        music.isPlayerIdle = false
                    }
                    activity.configurePreview(scenario.tasks ? fixtures : [])
                    activity.compactExpanded = false
                    coordinator.currentView = .home
                    vm.close()
                    vm.closedNotchSize.height = height

                    var modules: [String: String] = [:]
                    var frames: [String: CGRect] = [:]
                    let host = NSHostingView(rootView: ContentView(shelfAudioArrangementPreview: arrangement)
                        .environmentObject(vm)
                        .onPreferenceChange(NotchModuleAuditKey.self) { modules = $0 }
                        .onPreferenceChange(NotchModuleFrameAuditKey.self) { frames = $0 }
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                        .background(Color.black))
                    window.contentView = host
                    window.setContentSize(windowSize)
                    settle(); host.layoutSubtreeIfNeeded(); settle()
                    guard let camera = frames["camera"] else {
                        fatalError("Shelf/audio fixture did not publish camera geometry: \(scenario.name)")
                    }
                    verifyPresentation(abs(camera.midX - host.bounds.midX) <= 1,
                                       "Shelf/audio shifted the physical notch in \(scenario.name), height \(height)")
                    verifyPresentation(modules["bubble"] != nil,
                                       "Shelf glyph missing in \(scenario.name), height \(height)")
                    if let arrangement {
                        let expectedBubble = arrangement == .shelfWidgetAudioMinimal ? "widget" : "minimal"
                        let expectedMusic = arrangement == .shelfWidgetAudioMinimal ? "minimal" : "widget"
                        verifyPresentation(modules["bubble"] == expectedBubble,
                                           "Shelf was not outermost arrangement \(arrangement) in \(scenario.name): \(modules)")
                        verifyPresentation(modules["music"] == expectedMusic,
                                           "Audio mode did not swap with Shelf in \(scenario.name): \(modules)")
                        guard let bubble = frames["bubble"], let album = frames["album"] else {
                            fatalError("Shelf/audio pair omitted audited frames in \(scenario.name)")
                        }
                        verifyPresentation(bubble.minX <= album.minX + 1,
                                           "Shelf was not left of audio in \(scenario.name): \(bubble), \(album)")
                        let pairWidth = max(bubble.maxX, album.maxX) - min(bubble.minX, album.minX)
                        let expectedPairWidth = QuotaCompactMetrics.iconSize(height: height) + 26
                        verifyPresentation(abs(pairWidth - expectedPairWidth) <= 2,
                                           "Shelf/audio pair changed footprint in \(scenario.name), height \(height): \(pairWidth) vs \(expectedPairWidth)")
                    } else if let bubble = frames["bubble"] {
                        for name in ["quota", "task"] {
                            if let other = frames[name] {
                                verifyPresentation(bubble.minX <= other.minX + 1,
                                                   "Shelf was not the outermost left module in \(scenario.name): \(bubble), \(other)")
                            }
                        }
                    }
                    let arrangementName = arrangement?.rawValue ?? "none"
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        fatalError("Missing Shelf/audio fixture bitmap")
                    }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(
                        "Notch-shelf-audio-\(scenario.name)-h\(Int(height))-\(arrangementName).png"))
                    window.contentView = nil
                }
            }
        }
        print("Verified Shelf/audio fixed-footprint swaps, outermost-left order, paused/playing audio, quota/task combinations, and heights 24/32/38")
    }

    /// Exercise the actual pair NSView and its installed local scroll monitor.
    /// The preview feeds the production processScroll helper rather than
    /// posting global CGEvents, so the test stays deterministic and does not
    /// request input-monitor permission. A horizontal claim consumes its
    /// diagonal tail; a vertical claim remains deliverable to the inner Shelf
    /// view while blocking a later horizontal swap. Mouse events are sent to
    /// the same window to prove the scroll monitor leaves clicks and drags
    /// alone.
    @MainActor private static func captureBubbleShelfGestureRouting(output: URL) throws {
        var horizontalActions: [Bool] = []
        var audioClicks = 0
        var shelfClicks = 0
        var exportRequests = 0
        var auditedFrames: [String: CGRect] = [:]
        let state = BubbleShelfCompactState(
            itemCount: 1,
            isReceiving: false,
            onOpen: { shelfClicks += 1 },
            onVerticalSwipe: { _ in },
            writers: {
                exportRequests += 1
                return []
            },
            onHorizontalSwipe: { horizontalActions.append($0) })
        let root = BubbleShelfAudioPair(
            shelf: state,
            arrangement: .shelfMinimalAudioWidget,
            height: 32,
            widgetWidth: QuotaCompactMetrics.iconSize(height: 32),
            onAudioOpen: { audioClicks += 1 })
            .frame(width: QuotaCompactMetrics.iconSize(height: 32) + 26, height: 32)
            .onPreferenceChange(NotchModuleFrameAuditKey.self) { auditedFrames = $0 }
        let size = NSSize(width: QuotaCompactMetrics.iconSize(height: 32) + 26, height: 32)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        settle(); host.layoutSubtreeIfNeeded(); settle()
        guard let router = descendants(host).compactMap({ $0 as? BubbleShelfHorizontalScrollView }).first else {
            throw NSError(domain: "SettingsPreviewRunner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Shelf/audio pair has no native local-scroll view"])
        }
        verifyPresentation(router.window === window && router.hasLocalMonitorForPreview,
                           "Shelf/audio pair did not install its native local scroll monitor")

        func feed(_ dx: CGFloat, _ dy: CGFloat, _ phase: BubbleScrollPhase,
                  _ timestamp: TimeInterval, momentum: Bool = false) -> Bool {
            router.processPreviewScroll(deltaX: dx, deltaY: dy, phase: phase,
                                        isMomentum: momentum, timestamp: timestamp)
        }

        // Horizontal first: after the swap claim, the Y tail must be consumed
        // and cannot reach BubbleInteractionView's receive toggle.
        verifyPresentation(!feed(-2, 0, .began, 1.0), "Pair consumed a pre-threshold horizontal sample")
        verifyPresentation(feed(-4, 0, .changed, 1.05), "Pair did not consume its horizontal claim")
        verifyPresentation(feed(0, 8, .changed, 1.10), "Horizontal claim leaked a vertical tail")
        verifyPresentation(!feed(0, 0, .ended, 1.20), "Horizontal end was not delivered for nested reset")
        verifyPresentation(horizontalActions == [true], "Horizontal-first sequence did not swap exactly once")

        // Vertical first: the inner receive action stays eligible, but a later
        // X sample is consumed and cannot swap the pair.
        verifyPresentation(!feed(0, 2, .began, 2.0), "Pair consumed a pre-threshold vertical sample")
        verifyPresentation(!feed(0, 3, .changed, 2.05), "Vertical receive claim was hidden by the outer monitor")
        verifyPresentation(feed(-8, 0, .changed, 2.10), "Vertical claim allowed a later horizontal swap")
        verifyPresentation(!feed(0, 0, .ended, 2.20), "Vertical end was consumed instead of delivered")
        verifyPresentation(horizontalActions == [true], "Vertical-first sequence changed horizontal arrangement")

        // The opposite horizontal direction still works after the shared lock
        // resets at the end of the previous gesture.
        verifyPresentation(!feed(2, 0, .began, 3.0), "Pair consumed a pre-threshold reverse sample")
        verifyPresentation(feed(4, 0, .changed, 3.05), "Pair did not claim the reverse horizontal direction")
        verifyPresentation(!feed(0, 0, .ended, 3.20), "Reverse horizontal end was not delivered for nested reset")
        verifyPresentation(horizontalActions == [true, false], "Pair did not support both horizontal directions")

        guard let album = auditedFrames["album"] else {
            throw NSError(domain: "SettingsPreviewRunner", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Shelf/audio pair did not publish its audio hit frame"])
        }
        func mouseEvent(_ type: NSEvent.EventType, location: NSPoint, timestamp: TimeInterval,
                        number: Int, pressure: Float) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type, location: location,
                                                 modifierFlags: [], timestamp: timestamp,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: number, clickCount: 1, pressure: pressure) else {
                throw NSError(domain: "SettingsPreviewRunner", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Could not synthesize Shelf/audio mouse event"])
            }
            return event
        }
        let audioPoint = NSPoint(x: album.midX, y: album.midY)
        window.sendEvent(try mouseEvent(.leftMouseDown, location: audioPoint, timestamp: 4.0, number: 1, pressure: 1))
        window.sendEvent(try mouseEvent(.leftMouseUp, location: audioPoint, timestamp: 4.01, number: 2, pressure: 0))
        verifyPresentation(audioClicks == 1, "Audio click was intercepted by the Shelf scroll monitor")

        // The Shelf's drag recognizer still receives mouse movement. The
        // fixture records the export request but returns no pasteboard writer,
        // so it exercises routing without opening a real drag session or
        // touching the user's pasteboard.
        let shelfPoint = NSPoint(x: 7, y: size.height * 0.5)
        let dragPoint = NSPoint(x: 18, y: size.height * 0.5 + 1)
        window.sendEvent(try mouseEvent(.leftMouseDown, location: shelfPoint, timestamp: 5.0, number: 3, pressure: 1))
        window.sendEvent(try mouseEvent(.leftMouseDragged, location: dragPoint, timestamp: 5.05, number: 4, pressure: 1))
        window.sendEvent(try mouseEvent(.leftMouseUp, location: dragPoint, timestamp: 5.10, number: 5, pressure: 0))
        verifyPresentation(exportRequests == 1, "Shelf drag did not request an export exactly once")
        verifyPresentation(shelfClicks == 0, "Shelf drag or audio click was misread as a Shelf click")
        verifyPresentation(horizontalActions == [true, false], "Mouse drag changed Shelf/audio arrangement")

        let report = "Shelf/audio local monitor: X→Y consumed, Y→X locked vertical, both horizontal directions passed; audio click and mouse drag remained deliverable.\n"
        try Data(report.utf8).write(to: output.appendingPathComponent("Notch-shelf-audio-gesture-routing.txt"))
        print("Verified Shelf/audio local monitor axis lock, both directions, audio click, and Shelf drag routing")
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
        let savedCat = UserDefaults.standard.object(forKey: "notchCatEnabled")
        UserDefaults.standard.set(true, forKey: "notchCatEnabled")
        defer {
            if let savedCat { UserDefaults.standard.set(savedCat, forKey: "notchCatEnabled") }
            else { UserDefaults.standard.removeObject(forKey: "notchCatEnabled") }
        }
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
