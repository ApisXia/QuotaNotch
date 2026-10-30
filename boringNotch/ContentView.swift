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
    @Environment(\.displayScale) private var displayScale

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var quotaStore = QuotaNotchStore.shared

    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false


    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace


    @State private var measuredClosedWidth: CGFloat = 0
    @AppStorage(NotchUISize.defaultsKey) private var notchSizeRaw = NotchUISize.current.rawValue
    private var panelScale: CGFloat { NotchUISize.stored(notchSizeRaw, legacyComfortable: false).panelScale }
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
            notification: coordinator.sneakPeek.show ? coordinator.sneakPeek.type : nil
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
                // Match the actual camera gap so this hover target cannot cover wing controls.
                Color.clear.frame(width: max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top), height: vm.effectiveClosedNotchHeight)
                    .contentShape(Rectangle())
                    .onHover { handleHover($0) }
                    .onTapGesture { openFromPointer(explicit: true) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentOpenNotch)) { _ in
            coordinator.currentView = .activity; agentStore.notchReadEnabled = true
            if vm.notchState == .closed { doOpen() }
        }
        .onChange(of: vm.notchState) { _, state in
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
                    .modifier(NotchPanelScale(scale: vm.notchState == .open ? panelScale : 1, inner: openPanelInnerSize))
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
                
    }

    /// The space inside the opened shell, after its corner and edge padding.
    private var openPanelInnerSize: CGSize {
        let corner = NotchStyle.scalesCorners ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom
        return CGSize(width: max(0, vm.notchSize.width - 2 * (corner + 12)), height: max(0, vm.notchSize.height - 12))
    }

    /// Opened pages are laid out at their final width from the first frame. The shell then
    /// widens around them from the center and reveals them, instead of dragging leading-aligned
    /// content outward with its left edge.
    private var openContentWidth: CGFloat? {
        // The open size, not vm.notchSize, so pages keep their width while fading out on close.
        let corner = NotchStyle.scalesCorners ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom
        let inner = openNotchSize.width - 2 * (corner + 12)
        guard inner > 0 else { return nil }
        return inner / max(0.5, panelScale)
    }

    // Opening: the closed wings fold in toward the camera, then the panel's content appears.
    // Closing: the panel's content goes first, then the wings unfold from the camera.
    private var closedTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .notchFold.animation(.smooth(duration: 0.26).delay(0.16)),
                           removal: .notchFold.animation(.easeIn(duration: 0.14)))
    }
    private var openTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: AnyTransition.scale(scale: 0.92, anchor: .top).combined(with: .opacity)
                            .animation(.smooth(duration: 0.3).delay(0.12)),
                           removal: AnyTransition.scale(scale: 0.96, anchor: .top).combined(with: .opacity)
                            .animation(.easeIn(duration: 0.12)))
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        // Centered, so the closed wings fade out in place over the camera while the shell widens.
        VStack(alignment: .center, spacing: vm.notchState == .open ? 8 : 0) {
            Group {
                if vm.notchState == .closed {
                    PrimaryNotchLayout {
                        closedPrimaryContent
                        closedAccessoryContent
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: quotaStore.peek)
                    .transition(closedTransition)
                } else {
                    BoringHeader()
                        .frame(width: openContentWidth, alignment: .leading)
                        .transition(openTransition)
                }
            }
            .zIndex(2)

            if vm.notchState == .open {
                VStack {
                    if coordinator.currentView == .home {
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    } else {
                        // The pet keeps its column while Quota and Tasks swap beside it.
                        HStack(alignment: .top, spacing: 10) {
                            NotchPetColumn(page: coordinator.currentView)
                            Group {
                                if coordinator.currentView == .aiUsage { QuotaNotchView() } else { AgentNotchView() }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        // Both pages fill the same height, so the column keeps its size.
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(width: openContentWidth, alignment: .leading)
                .transition(openTransition)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
            }
        }
    }

    @ViewBuilder
    private var closedPrimaryContent: some View {
        if showQuotaWings {
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
            // Tasks show beside the quota pet, so they stay hidden while quota is.
            MusicLiveActivity().contentShape(Rectangle()).onTapGesture { coordinator.currentView = .home; doOpen() }
        } else {
            HStack(spacing: 0) {
                Color.clear.frame(width: 0)
                Color.clear.frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight).auditNotchFrame("camera")
                Color.clear.frame(width: 0)
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
        } else if compactPresentation == .combined && !vm.hideOnClosed, let peek = quotaStore.peek {
            // Music hides the numbers, so key quota moments get a short line, like a song title.
            Text(verbatim: peek)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.gray)
                .frame(height: 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .transition(.opacity)
                .auditNotchModule("peek")
        }
    }

    func MusicLiveActivity() -> some View {
        // Each side reaches as far as the quota pet's would, so the notch keeps one width
        // whether music, the pet, or both are showing.
        let notchSize = NotchUISize.stored(notchSizeRaw, legacyComfortable: false)
        let wing = QuotaPetArt.wingWidth(size: notchSize, notchHeight: vm.effectiveClosedNotchHeight, displayScale: displayScale)
        // The same album size as beside the pet.
        let album = QuotaPetArt.albumSize(size: notchSize, notchHeight: vm.effectiveClosedNotchHeight, displayScale: displayScale)
        return HStack(spacing: QuotaCompactMetrics.spacing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(width: album, height: album)
                .auditNotchFrame("album")
                .frame(width: wing, alignment: .leading)
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
                ).auditNotchFrame("camera")

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
            .frame(width: wing, alignment: .trailing)
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
        .auditNotchModule("music")
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func openFromPointer(explicit: Bool = false) {
        guard vm.notchState == .closed else { return }
        agentStore.notchReadEnabled = explicit
        let presentation = compactPresentation
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        let midpoint = screen?.frame.midX ?? NSEvent.mouseLocation.x
        let target = presentation.openingPage(pointerX: Double(NSEvent.mouseLocation.x),
                                               midpointX: Double(midpoint), isOpen: false)
        // Commit selection before open(), so the first expanded frame has the right content.
        switch target {
        case .home: coordinator.currentView = .home
        case .quota:
            // While tasks show beside the pet, the pet's side opens them, like tapping the pet.
            if showQuotaWings && agentStore.showAccessory {
                coordinator.currentView = .activity
            } else {
                if let provider = quotaStore.activePin?.provider { quotaStore.selectedProvider = provider }
                coordinator.currentView = .aiUsage
            }
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
                    
                    if self.vm.notchState == .open && !self.quotaStore.menuOpen {
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

/// Lays the opened panel out at its standard size and scales it to the chosen size, so every
/// control and text grows or shrinks together. The view structure is the same at every scale.
struct NotchPanelScale: ViewModifier {
    let scale: CGFloat
    let inner: CGSize
    func body(content: Content) -> some View {
        let active = scale != 1 && inner.width > 0 && inner.height > 0
        content
            .frame(width: active ? inner.width / scale : nil, height: active ? inner.height / scale : nil, alignment: .top)
            .scaleEffect(active ? scale : 1, anchor: .top)
            .frame(width: active ? inner.width : nil, height: active ? inner.height : nil, alignment: .top)
    }
}

/// The closed wings folding toward the camera: squeezed horizontally around the center,
/// a little flatter, and faded.
private struct NotchFold: ViewModifier {
    let folded: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: folded ? 0.25 : 1, y: folded ? 0.7 : 1, anchor: .center)
            .opacity(folded ? 0 : 1)
            .blur(radius: folded ? 1.5 : 0)
    }
}

extension AnyTransition {
    static var notchFold: AnyTransition {
        .modifier(active: NotchFold(folded: true), identity: NotchFold(folded: false))
    }
}
