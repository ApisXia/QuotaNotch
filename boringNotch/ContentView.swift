//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var quotaStore = QuotaNotchStore.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false


    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace


    @State private var measuredClosedWidth: CGFloat = 0
    @State private var taskWingOffset: CGFloat = 0
    @StateObject private var cat = NotchCatDirector()
    @AppStorage("notchCatEnabled") private var catEnabled = true
    @AppStorage("notchCatTaskCues") private var catTaskCues = true
    // Deterministic poses are injected only by the isolated screenshot runner.
    var catPreviewPose: CatPose? = nil

    @State private var catSpaces: [CatSide: CatWingSpace] = [:]
    @ObservedObject private var catRuntime = NotchCatRuntime.shared
    private var catCanAppear: Bool {
        catEnabled && !reduceMotion && !catRuntime.suspended && vm.notchState == .closed
            && !vm.hideOnClosed && vm.effectiveClosedNotchHeight >= 24
            && !eventPresentation.replacesPrimary && eventPresentation.accessory == nil
            && !coordinator.expandingView.show && !coordinator.helloAnimationRunning
    }
    private var displayedCatPose: CatPose { catCanAppear ? (catPreviewPose ?? cat.pose) : CatPose() }
    private var catWingOffset: CGFloat {
        let pose = displayedCatPose
        guard pose.active, let space = catSpaces[pose.side], space.canPeek else { return 0 }
        return min(space.room, pose.reservedWidth) * (pose.side == .left ? -0.5 : 0.5)
    }
    private var catRunID: String {
        let wings = CatSide.allCases.map { side in
            guard let space = catSpaces[side] else { return side.rawValue + ":absent" }
            return "\(side.rawValue):\(space.occupied):\(space.limit):\(space.height)"
        }.joined(separator: "|")
        return "\(catCanAppear)|\(vm.screenUUID ?? "")|\(wings)|\(String(describing: quotaStore.activePin))|\(String(describing: compactPresentation))|\(agentStore.compactExpanded)"
    }
    @ObservedObject private var agentStore = AgentActivityStore.shared

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private var animationSpring: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && NotchStyle.scalesCorners)
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && NotchStyle.scalesCorners)
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        measuredClosedWidth > 0 ? measuredClosedWidth : vm.closedNotchSize.width
    }

    private var eventPresentation: NotchEventPresentation {
        NotchEventPresentation(
            expanded: coordinator.expandingView.show ? coordinator.expandingView.type : nil,
            notification: coordinator.sneakPeek.show ? coordinator.sneakPeek.type : nil,
            greeting: coordinator.helloAnimationRunning
        )
    }

    private var compactPresentation: QuotaPresentation {
        guard vm.notchState == .closed else { return .none }
        return quotaStore.presentationPins.presentation(
            enabled: quotaStore.enabled,
            hidden: vm.hideOnClosed || vm.effectiveClosedNotchHeight <= 0,
            replacingPrimary: eventPresentation.replacesPrimary,
            musicPlaying: (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled
        )
    }

    private var showQuotaWings: Bool {
        compactPresentation == .quota || compactPresentation == .combined
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                styledNotch
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(reduceMotion ? nil : (vm.notchState == .open ? openAnimation : closeAnimation), value: vm.notchState)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        cat.pointer(hovering)
                        if vm.notchState == .open { handleHover(hovering) }
                    }
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.width
                    } action: { width in
                        if vm.notchState == .closed { measuredClosedWidth = width }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation(reduceMotion ? nil : .default) {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: quotaStore.menuOpen) { _, open in
                        if !open && !isHovering { handleHover(false) }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(250))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.quotaStore.menuOpen && !self.isHovering && self.vm.notchState == .open {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
            if vm.notchState == .closed {
                Color.clear.frame(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
                    .contentShape(Rectangle())
                    .onHover { cat.pointer($0, source: "camera"); handleHover($0) }
                    .onTapGesture { openFromPointer(explicit: true) }
            }
        }
        .onPreferenceChange(AgentWingOffsetKey.self) { taskWingOffset = $0 }
        .onPreferenceChange(CatWingSpacesKey.self) { catSpaces = $0 }
        .onChange(of: catEnabled) { _, enabled in
            if !enabled { cat.stop(); cat.clearCues() }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { cat.clearCues() } }
        .onChange(of: catTaskCues) { _, enabled in if !enabled { cat.clearCues() } }
        .onChange(of: agentStore.unread.map(\.eventID)) { _, _ in cat.revalidateCue() }
        .onDisappear { cat.stop() }
        .task(id: catRunID) {
            guard catCanAppear else { cat.stop(); return }
            await cat.run(spaces: catSpaces, screen: vm.screenUUID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentOpenNotch)) { _ in
            coordinator.currentView = .activity; agentStore.notchReadEnabled = true
            if vm.notchState == .closed { doOpen() }
        }
        .onChange(of: vm.notchState) { _, state in
            if state == .open { cat.pointer(false, source: "camera") }
            if state == .closed {
                agentStore.notchReadEnabled = false
                agentStore.expandedTaskID = nil
                agentStore.finishReading()
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .preferredColorScheme(.dark)
        .environment(\.locale, QuotaLanguage.locale)
        .environmentObject(vm)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .task { quotaStore.start(); AgentActivityStore.shared.start() }
    }

    private var styledNotch: some View {
         NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? NotchStyle.scalesCorners
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    // Size the painted shell, not a transparent wrapper around it.
                    // Short tabs must never center the entire notch away from the screen edge.
                    .frame(width: vm.notchState == .open ? vm.notchSize.width : nil,
                           height: vm.notchState == .open ? vm.notchSize.height : nil,
                           alignment: .top)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && NotchStyle.castsShadow)
                            ? .black.opacity(0.7) : .clear, radius: NotchStyle.scalesCorners ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                    .offset(x: vm.notchState == .closed ? taskWingOffset + catWingOffset : 0)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: taskWingOffset)
                
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading, spacing: vm.notchState == .open ? 8 : 0) {
            Group {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: { vm.closeHello() })
                        .frame(width: getClosedNotchSize().width, height: 80)
                        .padding(.top, 40)
                    Spacer()
                } else if vm.notchState == .closed {
                    PrimaryNotchLayout {
                        closedPrimaryContent
                            .environment(\.notchCatPose, displayedCatPose)
                        closedAccessoryContent
                    }
                } else {
                    BoringHeader()
                }
            }
            .zIndex(2)

            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .aiUsage:
                        QuotaNotchView()
                    case .activity:
                        AgentNotchView()
                    }
                }
                .transition(
                    reduceMotion ? .identity : .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
            }
        }
    }

    @ViewBuilder
    private var closedPrimaryContent: some View {
        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && Defaults[.showPowerStatusNotifications] {
            HStack(spacing: 0) {
                HStack {
                    Text(batteryModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 10)

                HStack {
                    BoringBatteryView(
                        batteryWidth: 30,
                        isCharging: batteryModel.isCharging,
                        isInLowPowerMode: batteryModel.isInLowPowerMode,
                        isPluggedIn: batteryModel.isPluggedIn,
                        levelBattery: batteryModel.levelBattery,
                        isForNotification: true
                    )
                }
                .frame(width: 76, alignment: .trailing)
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        } else if showQuotaWings {
            QuotaPinnedWings(centerWidth: vm.closedNotchSize.width - cornerRadiusInsets.closed.top,
                             height: vm.effectiveClosedNotchHeight,
                             showsMusic: compactPresentation == .combined,
                             albumArtNamespace: albumArtNamespace) { provider in
                quotaStore.selectedProvider = provider
                coordinator.currentView = .aiUsage
                doOpen()
            } onMusic: {
                coordinator.currentView = .home
                doOpen()
            }
            .transition(.opacity)
        } else if compactPresentation == .music {
            if agentStore.showAccessory {
                musicAndTaskWings
            } else {
                MusicLiveActivity().contentShape(Rectangle()).onTapGesture { coordinator.currentView = .home; doOpen() }
            }
        } else if agentStore.showAccessory && vm.effectiveClosedNotchHeight > 0 && !eventPresentation.replacesPrimary {
            AgentTaskOnlyWings(centerWidth: vm.closedNotchSize.width - cornerRadiusInsets.closed.top,
                               height: vm.effectiveClosedNotchHeight, open: openTasks)
        } else {
            HStack(spacing: 0) {
                Color.clear.frame(width: 0).catWing(.left, occupied: 0, height: vm.effectiveClosedNotchHeight)
                Color.clear.frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                Color.clear.frame(width: 0).catWing(.right, occupied: 0, height: vm.effectiveClosedNotchHeight)
            }
        }
    }

    @ViewBuilder
    private var closedAccessoryContent: some View {
        if let accessory = eventPresentation.accessory {
            if accessory.isSystemControl {
                SystemEventIndicatorModifier(
                    eventType: $coordinator.sneakPeek.type,
                    value: $coordinator.sneakPeek.value,
                    icon: $coordinator.sneakPeek.icon,
                    sendEventBack: { newVal in
                        switch coordinator.sneakPeek.type {
                        case .volume: VolumeManager.shared.setAbsolute(Float32(newVal))
                        case .brightness: BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                        case .backlight: KeyboardBacklightManager.shared.setAbsolute(value: Float32(newVal))
                        default: break
                        }
                    }
                )
                .padding(.top, 8)
                .padding(.bottom, 10)
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .transition(.opacity)
            } else if accessory == .music && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                HStack {
                    Image(systemName: "music.note")
                    GeometryReader { geo in
                        MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),
                                    textColor: NotchStyle.playerTinting ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray,
                                    minDuration: 1, frameWidth: geo.size.width)
                    }
                }
                .foregroundStyle(.gray)
                .frame(height: 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var musicAndTaskWings: some View {
        let height = vm.effectiveClosedNotchHeight
        let size = max(0, height - 12)
        return HStack(spacing: QuotaCompactMetrics.spacing) {
            Button { coordinator.currentView = .home; doOpen() } label: {
                Image(nsImage: musicManager.albumArt).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                    .frame(width: size, height: height)
                    .auditNotchModule("music")
            }.buttonStyle(.plain)
                .catWing(.left, occupied: size, height: height)
            Color.clear.frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top, height: height)
            AgentCompactDock(primaryWidth: 0, height: height, anchorWidth: size, widgetWidth: size, open: openTasks) { EmptyView() }
                .catWing(.right, occupied: size, height: height)
        }.frame(height: height)
    }

    func MusicLiveActivity() -> some View {
        let height = vm.effectiveClosedNotchHeight
        let size = max(0, height - 12)
        return HStack(spacing: QuotaCompactMetrics.spacing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

                .catWing(.left, occupied: size, height: height)
            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: NotchStyle.coloredSpectrogram
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    NotchStyle.coloredSpectrogram
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                    Rectangle()
                        .fill(
                            NotchStyle.coloredSpectrogram
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
            .catWing(.right, occupied: size, height: height)
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
        .auditNotchModule("music")
    }

    private func openTasks() {
        agentStore.notchReadEnabled = true
        coordinator.currentView = .activity
        doOpen()
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func openFromPointer(explicit: Bool = false) {
        guard vm.notchState == .closed else { return }
        agentStore.notchReadEnabled = explicit
        if agentStore.showAccessory && (compactPresentation == .none ||
            (compactPresentation == .combined && agentStore.compactExpanded)) {
            coordinator.currentView = .activity; doOpen(); return
        }
        let presentation = compactPresentation
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        let midpoint = screen?.frame.midX ?? NSEvent.mouseLocation.x
        let target = presentation.openingPage(pointerX: Double(NSEvent.mouseLocation.x),
                                               midpointX: Double(midpoint), isOpen: false)
        // Commit selection before open(), so the first expanded frame has the right content.
        switch target {
        case .home: coordinator.currentView = .home
        case .quota:
            if let provider = quotaStore.activePin?.provider { quotaStore.selectedProvider = provider }
            coordinator.currentView = .aiUsage
        case nil: break
        }
        doOpen()
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(NotchStyle.hoverDelay))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.openFromPointer()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !self.quotaStore.menuOpen {
                        self.vm.close()
                    }
                }
            }
        }
    }


}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
