//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @AppStorage("settingsSelectedTab") private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") { Label("通用", systemImage: "gearshape") }
                NavigationLink(value: "Quota") { Label("AI 额度", systemImage: "chart.pie") }
                NavigationLink(value: "Calendar") { Label("日历", systemImage: "calendar") }
                NavigationLink(value: "Media") { Label("音乐", systemImage: "music.note") }
                NavigationLink(value: "Appearance") { Label("外观与提示", systemImage: "circle.lefthalf.filled") }
                NavigationLink(value: "About") { Label("关于", systemImage: "info.circle") }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    QuotaAppearancePreferences()
                case "Calendar":
                    CalendarSettings()
                case "Media":
                    Media()
                case "Quota":
                    QuotaPreferences()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

struct GeneralSettings: View {
    @State private var language = QuotaLanguage.stored()
    private let startingLanguage = QuotaLanguage.atLaunch
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.showEmojis) var showEmojis
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.openNotchOnHover) var openNotchOnHover
    

    var body: some View {
        Form {
            Section("语言 / Language") {
                Picker("应用语言", selection: $language) {
                    Text("跟随系统").tag(QuotaLanguage.system)
                    Text(verbatim: "简体中文").tag(QuotaLanguage.chinese)
                    Text(verbatim: "English").tag(QuotaLanguage.english)
                }
                .onChange(of: language) { _, value in value.save() }
                if language != startingLanguage {
                    Text("重启后应用新语言，账户和固定设置会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重启并应用 / Restart to apply") { ApplicationRelauncher.restart() }
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle("Launch at login")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
            } header: {
                Text("System features")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("Notch height on notch displays")
                ) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch sizing")
            }

            NotchBehaviour()

            Section("快捷键") {
                KeyboardShortcuts.Recorder("展开／收起刘海", name: .toggleNotchOpen)
                KeyboardShortcuts.Recorder("显示音乐信息", name: .toggleSneakPeek)
            }
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("General")

    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text("Enable haptic feedback")
            }
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show battery percentage")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
            } header: {
                Text("Battery Information")
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.headline)
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }
                
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            
            Section {
                Picker("Option key behaviour", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(LocalizedStringKey(opt.rawValue)).tag(opt)
                    }
                }
                
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
            } header: {
                Text("Closed Notch")
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("HUDs")
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles


    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(LocalizedStringKey(controller.rawValue)).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(LocalizedStringKey(style.rawValue)).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Full screen behavior", selection: $hideNotchOption) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("Media playback live activity")
            }
            
            Section {
                MusicSlotConfigurationView()

            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("Show calendar")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Hide completed reminders")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Hide all-day events")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Auto-scroll to next event")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Always show full event titles")
            }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Calendar access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Calendar Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Reminder access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminder Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    let updaterController: SPUStandardUpdaterController
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("logo2").resizable().scaledToFit()
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("QuotaNotch").font(.title2.weight(.semibold))
                        Text("AI 额度、音乐与日历，留在刘海边上。")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("\(Bundle.main.releaseVersionNumber ?? "—") (\(Bundle.main.buildVersionNumber ?? "—"))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.padding(.vertical, 8)
            }
            Section("更新与支持") {
                Link("查看更新", destination: URL(string: "https://github.com/ApisXia/QuotaNotch/releases")!)
                Link("GitHub", destination: URL(string: "https://github.com/ApisXia/QuotaNotch")!)
                Text("当前通过 GitHub Releases 手动更新。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("致谢与许可") {
                Text("QuotaNotch by ApisXia")
                Link("基于 Boring Notch", destination: URL(string: "https://github.com/TheBoredTeam/boring.notch")!)
                Link("GPL-3.0 许可证", destination: URL(string: "https://github.com/ApisXia/QuotaNotch/blob/main/LICENSE")!)
                Link("第三方许可", destination: URL(string: "https://github.com/ApisXia/QuotaNotch/blob/main/THIRD_PARTY_LICENSES")!)
            }
        }
        .navigationTitle("About")
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.sliderColor) var sliderColor

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(LocalizedStringKey(option.rawValue))
                    }
                }
            } header: {
                Text("Media")
            }

        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }


}

struct Advanced: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    
    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker("Accent color", selection: $useCustomAccentColor) {
                        Text("System").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Using System Accent")
                                        .font(.body)
                                    Text("Your macOS system accent color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color Presets")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pick a Color")
                                        .font(.body)
                                    Text("Choose any color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)
                                        
                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent color")
            } footer: {
                Text("Choose between your system accent color or customize it with your own selection.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
            } header: {
                Text("Window Appearance")
            }
            
            Section {
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window Behavior")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Advanced")
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}

#Preview {
    HUD()
}
