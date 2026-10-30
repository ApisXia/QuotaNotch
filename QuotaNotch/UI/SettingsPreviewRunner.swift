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
        // Fixtures start at the standard size with the default pet.
        UserDefaults.standard.set(NotchUISize.standard.rawValue, forKey: NotchUISize.defaultsKey)
        UserDefaults.standard.removeObject(forKey: QuotaPetKind.defaultsKey)
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
        Defaults[.mediaController] = .spotify
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
            for page in ["General", "Appearance", "Connections", "Quota", "Activity", "Media", "Calendar", "System", "About"] {
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
        try captureNotchSwitching(output: output)
        // Every quota pet in every state, widget and minimal, four times the notch size.
        try capture(VStack(alignment: .leading, spacing: 16) {
            ForEach(QuotaPetKind.pets, id: \.self) { kind in
                HStack(spacing: 12) {
                    ForEach(QuotaPetMood.allCases, id: \.self) { mood in
                        VStack(spacing: 8) {
                            QuotaPetPixels(sprite: QuotaPetArt.sprite(kind, size: .widget, mood: mood, remaining: mood == .low ? 12 : (mood == .empty ? 0 : 64)),
                                           palette: QuotaPetArt.palette(kind, provider: .claude, tint: .original, remaining: mood == .low ? 12 : 64), scale: 4)
                            QuotaPetPixels(sprite: QuotaPetArt.sprite(kind, size: .minimal, mood: mood, remaining: mood == .low ? 12 : (mood == .empty ? 0 : 64)),
                                           palette: QuotaPetArt.palette(kind, provider: .claude, tint: .original, remaining: mood == .low ? 12 : 64), scale: 4)
                        }
                        .padding(8).background(.black, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }.padding(16).background(Color(white: 0.16)), width: 1080, name: "Quota-pets", output: output, height: 900)
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
        // The pet's summary cell and its music-time task tag, at four times the notch size.
        let summaries: [(Double?, [AgentRunState])] = [
            (72, []), (41, [.running]), (18, [.waiting, .running, .completed]),
            (64, [.waiting, .running, .running, .completed, .failed]), (nil, [])
        ]
        try capture(VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ForEach(Array(summaries.enumerated()), id: \.offset) { _, sample in
                    QuotaPetSummary(percent: sample.0, stale: false, kind: .bit, provider: .claude, tint: .original,
                                    fontSize: 12, tasks: sample.1)
                        .frame(width: 36, height: 32).scaleEffect(3).frame(width: 120, height: 100)
                        .background(.black, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            HStack(spacing: 14) {
                ForEach([AgentRunState.running, .waiting, .completed, .failed], id: \.self) { state in
                    QuotaPetTaskBadge(states: [state]).scaleEffect(4).frame(width: 80, height: 60)
                        .background(.black, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }.padding(16).background(Color(white: 0.16)).preferredColorScheme(.dark), width: 700,
            name: "Quota-pet-summary", output: output, height: 280)
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
        /// The quota module is the pet at its pixel scale, also in the shared music wing.
        func quotaWidth(height: CGFloat, size: NotchUISize, shared: Bool) -> CGFloat {
            QuotaPetArt.petWidth(size: size, notchHeight: height, displayScale: host.window?.backingScaleFactor ?? 1)
        }
        func verifyGeometry(_ label: String, widget: CGFloat, quota: CGFloat? = nil, wing: CGFloat? = nil) {
            guard let camera = renderedFrames["camera"] else { fatalError("Missing camera geometry in \(label)") }
            verifyPresentation(abs(camera.midX - host.bounds.midX) <= 1, "Physical notch shifted in \(label): \(camera)")
            if let album = renderedFrames["album"] {
                verifyPresentation(abs(album.width - widget) <= 1, "Album stretched in \(label): \(album)")
                // The album is centered in its side.
                verifyPresentation(abs(album.midX - (camera.minX - QuotaCompactMetrics.spacing - (wing ?? quota ?? widget) / 2)) <= 1,
                    "Album moved off the middle of its side in \(label): \(album), camera \(camera)")
            }
            for name in ["quota", "task"] {
                if let mode = renderedModules[name], let frame = renderedFrames[name] {
                    let expected = mode == "minimal" ? CGFloat(16) : (name == "quota" ? (quota ?? widget) : widget)
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
        func blackWidth(_ bitmap: NSBitmapImageRep) -> Int {
            let row = max(1, Int(5 * CGFloat(bitmap.pixelsHigh) / host.bounds.height))
            let points = (0..<bitmap.pixelsWide).filter { x in
                guard let c = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                return max(c.redComponent, max(c.greenComponent, c.blueComponent)) < 0.06
            }
            return (points.last ?? 0) - (points.first ?? 0)
        }
        func snapshot(_ name: String) throws -> NSBitmapImageRep {
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
            let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2)!.usingColorSpace(.deviceRGB)!
            precondition(max(color.redComponent, max(color.greenComponent, color.blueComponent)) < 0.06, "Closed notch detached in \(name)")
            return bitmap
        }
        /// The pet never swaps with tasks: tasks sit beside it (dots) or on it (a tag with music),
        /// and are hidden whenever quota is.
        func expectedModules(quota: Bool, music: Bool, tasks: Bool) -> [String: String] {
            var expected: [String: String] = [:]
            if music { expected["music"] = "widget" }
            if quota {
                expected["quota"] = "widget"
                if !music { expected["summary"] = "widget" }
                if music && tasks { expected["tasks"] = "badge" }
            }
            return expected
        }
        func verifyPet(_ label: String, height: CGFloat, size: NotchUISize, quota: Bool) {
            // The album's expected size; the other modules use the pet's width.
            let widget = QuotaPetArt.albumSize(size: size, notchHeight: height, displayScale: host.window?.backingScaleFactor ?? 1).width
            verifyGeometry(label, widget: widget, quota: quotaWidth(height: height, size: size, shared: false),
                           wing: QuotaPetArt.wingWidth(size: size, notchHeight: height, displayScale: host.window?.backingScaleFactor ?? 1))
            guard let camera = renderedFrames["camera"] else { return }
            for name in ["summary", "tasks"] {
                if let frame = renderedFrames[name] {
                    verifyPresentation(frame.maxX <= camera.minX + 1 || frame.minX >= camera.maxX - 1,
                                       "\(name) overlaps physical notch in \(label)")
                }
            }
        }
        let cases: [(name: String, quota: Bool, music: Bool, tasks: Bool)] = [
            ("quota", true, false, false), ("quota-tasks", true, false, true),
            ("music", true, true, false), ("music-tasks", true, true, true),
            ("music-only", false, true, false), ("music-only-tasks", false, true, true),
            ("empty", false, false, false), ("tasks-only", false, false, true)
        ]
        let pairs = [("quota", "quota-tasks"), ("music", "music-tasks"),
                     ("music-only", "music-only-tasks"), ("empty", "tasks-only")]
        coordinator.musicLiveActivityEnabled = true
        for size in [NotchUISize.standard, .large, .small] {
            UserDefaults.standard.set(size.rawValue, forKey: NotchUISize.defaultsKey)
            for headerHeight: CGFloat in [24, 32, 38] {
                vm.closedNotchSize.height = headerHeight
                var widths: [String: Int] = [:]
                for scenario in cases {
                    QuotaNotchStore.shared.configureSettingsPreview(paused: !scenario.quota)
                    MusicManager.shared.isPlaying = scenario.music
                    MusicManager.shared.isPlayerIdle = !scenario.music
                    activity.configurePreview(scenario.tasks ? fixtures : [])
                    settle(); host.layoutSubtreeIfNeeded()
                    let label = "\(scenario.name)-\(Int(headerHeight))-\(size.rawValue)"
                    let expected = expectedModules(quota: scenario.quota, music: scenario.music, tasks: scenario.tasks)
                    verifyPresentation(renderedModules == expected, "Wrong presentation in \(label): \(renderedModules), expected \(expected)")
                    verifyPet(label, height: headerHeight, size: size, quota: scenario.quota)
                    modeAudit.append(["case": scenario.name, "height": headerHeight, "size": size.rawValue, "rendered": renderedModules])
                    let bitmap = try snapshot("Notch-closed-\(label).png")
                    widths[scenario.name] = blackWidth(bitmap)
                    if scenario.name == "music" {
                        QuotaNotchStore.shared.setPreviewPeek(QuotaNotchStore.peekText(provider: .claude,
                            window: QuotaWindow(id: "five_hour", title: "5 小时", remainingPercent: 18,
                                                resetsAt: Date().addingTimeInterval(2 * 3600 + 600)), now: Date()))
                        settle(); host.layoutSubtreeIfNeeded()
                        verifyPresentation(renderedModules["peek"] == "widget", "Quota peek missing in \(label)")
                        verifyPet(label + "-peek", height: headerHeight, size: size, quota: true)
                        _ = try snapshot("Notch-closed-\(label)-peek.png")
                        QuotaNotchStore.shared.setPreviewPeek(nil)
                    }
                }
                for (plain, busy) in pairs {
                    verifyPresentation(abs(widths[plain]! - widths[busy]!) <= 1,
                        "Tasks changed the notch width: \(plain) vs \(busy) at \(headerHeight), \(size.rawValue)")
                }
            }
        }
        UserDefaults.standard.set(NotchUISize.standard.rawValue, forKey: NotchUISize.defaultsKey)
        // Music starting and stopping keeps the same modules on each side.
        QuotaNotchStore.shared.configureSettingsPreview(paused: false)
        activity.configurePreview(fixtures)
        for headerHeight: CGFloat in [24, 32, 38] {
            vm.closedNotchSize.height = headerHeight
            for playback in ["playing", "paused", "idle", "resumed"] {
                MusicManager.shared.isPlaying = playback == "playing" || playback == "resumed"
                MusicManager.shared.isPlayerIdle = playback == "idle"
                settle(); host.layoutSubtreeIfNeeded()
                let expected = expectedModules(quota: true, music: playback != "idle", tasks: true)
                verifyPresentation(renderedModules == expected, "Playback transition \(playback) retained the wrong presentation: \(renderedModules)")
                verifyPet("\(playback)-\(headerHeight)", height: headerHeight, size: .standard, quota: true)
                modeAudit.append(["case": playback, "height": headerHeight, "rendered": renderedModules])
                _ = try snapshot("Notch-transition-\(Int(headerHeight))-\(playback).png")
            }
        }
        try JSONSerialization.data(withJSONObject: modeAudit, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("Notch-presentation-audit.json"))
        print("Verified \(modeAudit.count) actual rendered presentations, including playback transitions")
        MusicManager.shared.isPlaying = false
        MusicManager.shared.isPlayerIdle = true
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
