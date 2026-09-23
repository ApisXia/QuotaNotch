// SPDX-License-Identifier: GPL-3.0-only
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsSelectedTab") private var selectedTab = "General"
    // Observe the actual preferences without destroying page state when a color changes.
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") { Label("通用", systemImage: "gearshape") }
                NavigationLink(value: "Quota") { Label("AI 额度", systemImage: "chart.pie") }
                NavigationLink(value: "Activity") { Label(AgentText.t("任务监控", "Task monitor"), systemImage: "square.stack.3d.up") }
                NavigationLink(value: "Media") { Label("音乐", systemImage: "music.note") }
                NavigationLink(value: "Calendar") { Label("Calendars & Reminders", systemImage: "calendar") }
                NavigationLink(value: "Appearance") { Label("外观", systemImage: "circle.lefthalf.filled") }
                NavigationLink(value: "System") { Label("System Indicators", systemImage: "slider.horizontal.3") }
                NavigationLink(value: "About") { Label("关于", systemImage: "info.circle") }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedTab {
                case "Quota": QuotaPreferences()
                case "Activity": AgentActivitySettings()
                case "Media": Media()
                case "Calendar": CalendarSettings()
                case "Appearance": Appearance()
                case "System": HUD()
                case "About": About(updaterController: updaterController ?? SPUStandardUpdaterController(
                    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
                default: GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .formStyle(.grouped)
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(settingsAccent)
        .onAppear {
            let pages = ["General", "Quota", "Activity", "Media", "Calendar", "Appearance", "System", "About"]
            if !pages.contains(selectedTab) { selectedTab = "General" }
        }
    }

    private var settingsAccent: Color {
        if useCustomAccentColor, let data = customAccentColorData,
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return Color(nsColor: color)
        }
        return .accentColor
    }
}

struct GeneralSettings: View {
    @State private var language = QuotaLanguage.stored()
    private let startingLanguage = QuotaLanguage.atLaunch
    @State private var screens: [(uuid: String, name: String)] = []
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) private var automaticallySwitchDisplay
    @Default(.hideNotchOption) private var hideNotchOption

    var body: some View {
        Form {
            Section("语言 / Language") {
                SettingsField("应用语言") {
                    Picker("应用语言", selection: $language) {
                        Text("跟随系统").tag(QuotaLanguage.system)
                        Text(verbatim: "简体中文").tag(QuotaLanguage.chinese)
                        Text(verbatim: "English").tag(QuotaLanguage.english)
                    }
                }
                .onChange(of: language) { _, value in value.save() }
                if language != startingLanguage {
                    SettingsHint("重启后应用新语言，账户和固定设置会保留。")
                    Button("重启并应用 / Restart to apply") { ApplicationRelauncher.restart() }
                }
            }
            Section("System features") {
                Defaults.Toggle(key: .menubarIcon) { Text("Show menu bar icon").fixedSize(horizontal: false, vertical: true) }
                LaunchAtLogin.Toggle(QuotaText.localized("Launch at login"))
            }
            Section("Displays") {
                Defaults.Toggle(key: .showOnAllDisplays) { Text("Show on all displays").fixedSize(horizontal: false, vertical: true) }
                    .onChange(of: showOnAllDisplays) {
                        NotificationCenter.default.post(name: .showOnAllDisplaysChanged, object: nil)
                    }
                SettingsField("Preferred display") {
                    Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                        if coordinator.preferredScreenUUID == nil { Text("Choose a display").tag(nil as String?) }
                        if let saved = coordinator.preferredScreenUUID, !screens.contains(where: { $0.uuid == saved }) {
                            Text("Saved display (disconnected)").tag(saved as String?)
                        }
                        ForEach(screens, id: \.uuid) { screen in
                            Text(screen.name).tag(screen.uuid as String?)
                        }
                    }
                }
                .disabled(showOnAllDisplays)
                Defaults.Toggle(key: .automaticallySwitchDisplay) { Text("Automatically switch displays").fixedSize(horizontal: false, vertical: true) }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(name: .automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
                if showOnAllDisplays {
                    SettingsHint("Display preferences are saved and apply when showing on one display.")
                }
                SettingsField("Full screen behavior") {
                    Picker("Full screen behavior", selection: $hideNotchOption) {
                        Text("Hide for all apps").tag(HideNotchOption.always)
                        Text("Never hide").tag(HideNotchOption.never)
                    }
                }
                SettingsHint("Applies to the entire notch, including music and AI usage.")
            }
            Section("Notch behavior") {
                Defaults.Toggle(key: .openNotchOnHover) { Text("Open notch on hover").fixedSize(horizontal: false, vertical: true) }
                Defaults.Toggle(key: .enableHaptics) { Text("Enable haptic feedback").fixedSize(horizontal: false, vertical: true) }
                Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
                Defaults.Toggle(key: .extendHoverArea) { Text("Extend hover area").fixedSize(horizontal: false, vertical: true) }
                Defaults.Toggle(key: .hideTitleBar) { Text("Cover menu bar behind the notch").fixedSize(horizontal: false, vertical: true) }
                Defaults.Toggle(key: .showOnLockScreen) { Text("Show notch on lock screen").fixedSize(horizontal: false, vertical: true) }
                Defaults.Toggle(key: .hideFromScreenRecording) { Text("Hide from screen recording").fixedSize(horizontal: false, vertical: true) }
            }
            Section("快捷键") {
                SettingsField("展开／收起刘海") { KeyboardShortcuts.Recorder(for: .toggleNotchOpen) }
                SettingsField("显示音乐信息") { KeyboardShortcuts.Recorder(for: .toggleSneakPeek) }
            }
        }
        .navigationTitle("General")
        .toolbar { Button("Quit app") { NSApp.terminate(self) } }
        .onAppear { reloadScreens() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in reloadScreens() }
    }

    private func reloadScreens() {
        screens = NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { (uuid: $0, name: screen.localizedName) }
        }
    }

}

struct HUD: View {
    @Default(.optionKeyAction) private var optionKeyAction
    @Default(.hudReplacement) private var hudReplacement
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section("Volume & Brightness") {
                Defaults.Toggle(key: .hudReplacement) { Text("Replace system HUD").fixedSize(horizontal: false, vertical: true) }
                    .toggleStyle(.switch)
                    .disabled(!accessibilityAuthorized && !hudReplacement)
                SettingsHint("Volume and brightness appear below the current notch content in every display mode.")
                if !accessibilityAuthorized {
                    SettingsHint("Accessibility access is required to replace the system HUD.")
                    Button("Request Accessibility") {
                        XPCHelperClient.shared.requestAccessibilityAuthorization()
                    }
                } else if !hudReplacement {
                    SettingsHint("Preferences are saved and apply when this feature is enabled.")
                }
            }
            Section("Controls") {
                SettingsField("Option key behaviour") {
                    Picker("Option key behaviour", selection: $optionKeyAction) {
                        ForEach(OptionKeyAction.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                }
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) { Text("Show percentage").fixedSize(horizontal: false, vertical: true) }
            }
            .disabled(!hudReplacement || !accessibilityAuthorized)
            Section("Battery") {
                Defaults.Toggle(key: .showBatteryIndicator) { Text("Show battery indicator").fixedSize(horizontal: false, vertical: true) }
                Defaults.Toggle(key: .showPowerStatusNotifications) { Text("Show power status notifications").fixedSize(horizontal: false, vertical: true) }
                Defaults.Toggle(key: .showBatteryPercentage) { Text("Show battery percentage").fixedSize(horizontal: false, vertical: true) }
                    .disabled(!showBatteryIndicator && !showPowerStatusNotifications)
                Defaults.Toggle(key: .showPowerStatusIcons) { Text("Show power status icons").fixedSize(horizontal: false, vertical: true) }
                    .disabled(!showBatteryIndicator)
                SettingsHint("Power status notifications work independently of the battery indicator. Status icons are always shown in notifications.")
            }
        }
        .navigationTitle("System Indicators")
        #if !SETTINGS_PREVIEW
        .task { accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized() }
        .onAppear { XPCHelperClient.shared.startMonitoringAccessibilityAuthorization() }
        .onDisappear { XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization() }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool { accessibilityAuthorized = granted }
        }
    }
}

struct Media: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.waitInterval) private var waitInterval
    @Default(.mediaController) private var mediaController
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) private var sneakPeekStyles
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    var body: some View {
        Form {
            Section("Media Source") {
                SettingsField("Music Source") {
                    Picker("Music Source", selection: Binding(
                        get: { musicManager.isNowPlayingDeprecated && mediaController == .nowPlaying ? .appleMusic : mediaController },
                        set: { mediaController = $0 }
                    )) {
                        ForEach(availableMediaControllers) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(name: .mediaControllerChanged, object: nil)
                }
                if musicManager.isNowPlayingDeprecated && mediaController == .nowPlaying {
                    SettingsHint("Now Playing is unavailable. Apple Music is used instead.")
                }
                if mediaController == .youtubeMusic {
                    SettingsHint("YouTube Music requires Pear Desktop.")
                    Link("Get Pear Desktop", destination: URL(string: "https://github.com/pear-devs/pear-desktop")!)
                }
            }
            Section("Media playback live activity") {
                Toggle("Show music live activity", isOn: $coordinator.musicLiveActivityEnabled)
                SettingsHint("Shows album art and playback activity in the closed notch.")
                SettingsField("Media inactivity timeout") {
                    HStack(spacing: 8) {
                        Text("\(waitInterval, specifier: "%.0f") seconds").foregroundStyle(.secondary).monospacedDigit()
                        Stepper("Media inactivity timeout", value: $waitInterval, in: 0...10, step: 1).labelsHidden()
                            .fixedSize()
                    }
                }
                .disabled(!coordinator.musicLiveActivityEnabled)
            }
            Section("Playback Notifications") {
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                SettingsField("Sneak Peek Style") {
                    Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                        ForEach(SneakPeekStyle.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                }
                .disabled(!enableSneakPeek)
                if !enableSneakPeek { SettingsHint("Preferences are saved and apply when this feature is enabled.") }
            }
            Section("Media controls") {
                MusicSlotConfigurationView()
            }

        }
        .navigationTitle("Media")
    }
    private var availableMediaControllers: [MediaControllerType] {
        musicManager.isNowPlayingDeprecated ? MediaControllerType.allCases.filter { $0 != .nowPlaying } : MediaControllerType.allCases
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) private var showCalendar
    @State private var requestingAccess = false

    var body: some View {
        Form {
            Section("Display") {
                Defaults.Toggle(key: .showCalendar) { Text("Show calendar").fixedSize(horizontal: false, vertical: true) }
                if !showCalendar { SettingsHint("Preferences are saved and apply when this feature is enabled.") }
                Group {
                    Defaults.Toggle(key: .hideCompletedReminders) { Text("Hide completed reminders").fixedSize(horizontal: false, vertical: true) }
                    Defaults.Toggle(key: .hideAllDayEvents) { Text("Hide all-day events").fixedSize(horizontal: false, vertical: true) }
                    Defaults.Toggle(key: .autoScrollToNextEvent) { Text("Auto-scroll to next event").fixedSize(horizontal: false, vertical: true) }
                    Defaults.Toggle(key: .showFullEventTitles) { Text("Always show full event titles").fixedSize(horizontal: false, vertical: true) }
                }.disabled(!showCalendar)
            }
            Section("Calendars") {
                calendarPermission(for: .event, status: calendarManager.calendarAuthorizationStatus)
                if calendarManager.calendarAuthorizationStatus == .fullAccess {
                    if calendarManager.eventCalendars.isEmpty { SettingsHint("No calendars found.") }
                    ForEach(calendarManager.eventCalendars, id: \.id) { calendar in calendarRow(calendar) }
                }
            }
            Section("Reminders") {
                calendarPermission(for: .reminder, status: calendarManager.reminderAuthorizationStatus)
                if calendarManager.reminderAuthorizationStatus == .fullAccess {
                    if calendarManager.reminderLists.isEmpty { SettingsHint("No reminder lists found.") }
                    ForEach(calendarManager.reminderLists, id: \.id) { calendar in calendarRow(calendar) }
                }
            }
        }
        .navigationTitle("Calendars & Reminders")
        .task { await refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermissions() }
        }
    }

    private func calendarRow(_ calendar: CalendarModel) -> some View {
        Toggle(isOn: Binding(get: { calendarManager.getCalendarSelected(calendar) }, set: { value in
            Task { await calendarManager.setCalendarSelected(calendar, isSelected: value) }
        })) {
            Text(calendar.title).fixedSize(horizontal: false, vertical: true)
        }
        .tint(lighterColor(from: calendar.color))
        .disabled(!showCalendar)
    }

    @ViewBuilder private func calendarPermission(for type: EKEntityType, status: EKAuthorizationStatus) -> some View {
        let access = SettingsAccessState(calendarStatus: status)
        if access != .allowed {
            SettingsPermissionNotice(state: access) {
                if access == .notRequested || access == .limited {
                    requestingAccess = true
                    Task {
                        if type == .event { await calendarManager.checkCalendarAuthorization(promptIfNeeded: true) }
                        else { await calendarManager.checkReminderAuthorization(promptIfNeeded: true) }
                        requestingAccess = false
                    }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(type == .event ? "Calendars" : "Reminders")") {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(requestingAccess)
        }
    }
    private func refreshPermissions() async {
        await calendarManager.checkCalendarAuthorization(promptIfNeeded: false)
        await calendarManager.checkReminderAuthorization(promptIfNeeded: false)
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    return Color(red: min(1, r + (1-r)*amount), green: min(1, g + (1-g)*amount), blue: min(1, b + (1-b)*amount), opacity: a)
}

extension SettingsAccessState {
    init(calendarStatus: EKAuthorizationStatus) {
        switch calendarStatus {
        case .notDetermined: self = .notRequested
        case .fullAccess: self = .allowed
        case .writeOnly: self = .limited
        case .restricted: self = .restricted
        case .denied: self = .denied
        @unknown default: self = .unavailable
        }
    }
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
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
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
            NotchCatSettings()
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
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                    }
                                }
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
                SettingsHint("Choose between your system accent color or customize it with your own selection.")
            }
            .onAppear {
                initializeAccentColorState()
            }
            
            Section("General") {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) { Text("Show settings icon in notch").fixedSize(horizontal: false, vertical: true) }
            }


        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
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
