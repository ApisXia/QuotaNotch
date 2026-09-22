// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BubbleShelfCompactState {
    let itemCount: Int
    let isReceiving: Bool
    let onOpen: () -> Void
    let onVerticalSwipe: (Bool) -> Void
    let writers: () -> [NSPasteboardWriting]
    let onHorizontalSwipe: (Bool) -> Void

    init(itemCount: Int, isReceiving: Bool, onOpen: @escaping () -> Void,
         onVerticalSwipe: @escaping (Bool) -> Void,
         writers: @escaping () -> [NSPasteboardWriting],
         onHorizontalSwipe: @escaping (Bool) -> Void = { _ in }) {
        self.itemCount = itemCount
        self.isReceiving = isReceiving
        self.onOpen = onOpen
        self.onVerticalSwipe = onVerticalSwipe
        self.writers = writers
        self.onHorizontalSwipe = onHorizontalSwipe
    }
}

@MainActor
struct BubbleShelfView: View {
    @ObservedObject private var store = BubbleShelfStore.shared
    @ObservedObject private var collector = BubbleCollectorController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(AgentText.t("收纳", "Shelf"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                Spacer(minLength: 8)
                BubbleReceivingToggle()
                    .frame(width: 150)
                if !store.items.isEmpty {
                    Button { store.clear() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(AgentText.t("清空收纳", "Clear Shelf"))
                }
            }
            .frame(height: 24)

            HStack(spacing: 7) {
                Circle()
                    .fill(collector.availability == .ready && store.isReceiving ? Color.green.opacity(0.9) : Color.white.opacity(0.32))
                    .frame(width: 5, height: 5)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if collector.availability == .accessibilityRequired {
                    Button(AgentText.t("允许访问", "Allow Access")) {
                        collector.requestAccessibilityFromUserAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if store.isReceiving && collector.finderAutomationState != .enabled {
                    Button(AgentText.t("允许 Finder", "Allow Finder")) {
                        collector.requestFinderAutomationFromUserAction()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 9, weight: .medium))
                }
            }
            .frame(height: 16)

            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)

            if store.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AgentText.t("暂无内容", "Nothing saved yet"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(AgentText.t("拖入文件，或开启接收后点击附近的气泡预览。", "Drop files here, or enable receiving and click a nearby preview."))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.items) { item in
                            BubbleShelfItemRow(item: item, store: store)
                        }
                    }
                }
                .frame(minHeight: 56, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            BubbleShelfDropTarget { _ in }
        }
        .accessibilityIdentifier("bubble-shelf-panel")
    }

    private var statusText: String {
        if store.storageIssue != nil {
            return AgentText.t("已保存的收纳内容暂时无法读取。", "The saved Shelf could not be read right now.")
        }
        if store.exportIssue != nil {
            return AgentText.t("部分原始内容暂时不可用，仍可导出其他项目。", "Some original items are unavailable; the rest can still be exported.")
        }
        if let result = store.lastImportResult,
           result.succeeded || result.skippedCount > 0 || !result.errors.isEmpty {
            return Self.summary(for: result)
        }
        if store.isReceiving && collector.finderAutomationState == .denied {
            return AgentText.t("Finder 访问未开启，请在系统设置的自动化中允许后重试。",
                               "Finder access is off. Allow QuotaNotch in Automation settings, then retry.")
        }
        switch collector.availability {
        case .disabled:
            return store.isReceiving
                ? AgentText.t("等待接收所选内容", "Ready to capture selected content")
                : AgentText.t("接收已暂停；已保存内容仍可查看和拖出。", "Receiving is paused. Saved items remain available.")
        case .ready:
            return AgentText.t("等待接收所选内容", "Ready to capture selected content")
        case .accessibilityRequired:
            return AgentText.t("需要辅助功能访问才能读取所选内容。", "Accessibility access is needed to preview selected content.")
        case .selectionUnavailable:
            return AgentText.t("当前应用没有可读取的所选内容。", "There is no readable selection in the current app.")
        case .captured:
            return AgentText.t("预览已捕获。", "Preview captured.")
        case .error:
            return AgentText.t("暂时无法读取所选内容。", "Selected content is temporarily unavailable.")
        }
    }

    private static func summary(for result: BubbleShelfImportResult) -> String {
        var parts: [String] = []
        if result.addedCount > 0 { parts.append(AgentText.t("新增 \(result.addedCount) 项", "Added \(result.addedCount)")) }
        if result.duplicateCount > 0 { parts.append(AgentText.t("已有 \(result.duplicateCount) 项", "Already saved \(result.duplicateCount)")) }
        if result.skippedCount > 0 { parts.append(AgentText.t("跳过 \(result.skippedCount) 项", "Skipped \(result.skippedCount)")) }
        for error in result.errors {
            let lower = error.lowercased()
            if lower.contains("full") {
                parts.append(AgentText.t("收纳已满，请先移除一项", "Shelf is full; remove an item first"))
            } else if lower.contains("paused") {
                parts.append(AgentText.t("接收已暂停", "Receiving is paused"))
            } else if lower.contains("pasteboard") || lower.contains("promised") || lower.contains("unsupported") {
                parts.append(AgentText.t("此拖放内容暂不支持", "This dropped content is not supported"))
            } else if lower.contains("unavailable") || lower.contains("could not be read") {
                parts.append(AgentText.t("部分内容无法读取", "Some content could not be read"))
            } else if lower.contains("save") {
                parts.append(AgentText.t("无法保存到收纳", "The item could not be saved to Shelf"))
            } else {
                parts.append(AgentText.t("部分内容无法导入", "Some content could not be imported"))
            }
        }
        return parts.isEmpty ? AgentText.t("没有可导入的内容", "No importable content") : parts.joined(separator: " · ")
    }
}

@MainActor
struct BubbleReceivingToggle: View {
    @ObservedObject private var store = BubbleShelfStore.shared
    @ObservedObject private var collector = BubbleCollectorController.shared

    private var receiving: Binding<Bool> {
        Binding(
            get: { store.isReceiving },
            set: { enabled in
                if enabled { collector.startReceivingFromUser() }
                else { collector.pauseReceiving() }
            }
        )
    }

    var body: some View {
        Toggle(isOn: receiving) {
            Label(
                store.isReceiving ? AgentText.t("等待接收", "Receiving") : AgentText.t("暂停接收", "Paused"),
                systemImage: store.isReceiving ? "arrow.down.to.line.compact" : "pause.circle"
            )
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
        }
        .toggleStyle(.switch)
        .tint(.mint)
        .accessibilityIdentifier("bubble-receiving-toggle")
    }
}

@MainActor
struct BubbleShelfSettingsView: View {
    @ObservedObject private var store = BubbleShelfStore.shared
    @ObservedObject private var collector = BubbleCollectorController.shared

    var body: some View {
        Form {
            Section(AgentText.t("接收与收纳", "Receiving and Shelf")) {
                BubbleReceivingToggle()
                Text(AgentText.t("开启后，所选内容会在附近显示预览；点击预览才会保存。暂停只停止接收，不会删除已保存内容。", "When enabled, a nearby preview follows supported selections. Click it to save. Pausing stops capture without deleting saved items."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if collector.availability == .accessibilityRequired {
                    Text(AgentText.t("需要辅助功能访问才能显示其他应用中的所选内容。", "Accessibility access is needed to preview selections in other apps."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(AgentText.t("打开访问设置", "Allow Access")) {
                        collector.requestAccessibilityFromUserAction()
                    }
                }
                if store.isReceiving {
                    HStack(spacing: 8) {
                        Text(AgentText.t("Finder 文件选择", "Finder file selection"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if collector.finderAutomationState == .enabled {
                            Label(AgentText.t("已允许", "Allowed"), systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(AgentText.t("允许读取 Finder", "Allow Finder Access")) {
                                collector.requestFinderAutomationFromUserAction()
                            }
                        }
                    }
                    if collector.finderAutomationState == .denied {
                        Text(AgentText.t("Finder 自动化访问未开启，请允许后重试。",
                                         "Finder Automation access is off. Allow it, then retry."))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                LabeledContent(AgentText.t("已保存", "Saved")) {
                    Text(AgentText.t("\(store.items.count) / 80", "\(store.items.count) / 80"))
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle(AgentText.t("收纳", "Shelf"))
    }
}

private struct BubbleShelfItemRow: View {
    let item: BubbleShelfItem
    @ObservedObject var store: BubbleShelfStore

    var body: some View {
        HStack(spacing: 11) {
            BubbleShelfDragHandle(writers: { store.exportItems([item.id]) }, preview: { store.thumbnail(for: item) ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 24, height: 24)) })
                .frame(width: 28, height: 28)
                .overlay { BubbleShelfArtwork(item: item, store: store, size: 22).allowsHitTesting(false) }
                .accessibilityLabel(AgentText.t("拖动 \(item.title)", "Drag \(item.title)"))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(kindTitle(item.kind))
                    if item.availability == .unavailable {
                        Text(AgentText.t("原文件不可用", "Original unavailable"))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                    Text(item.addedAt, style: .relative)
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { store.remove(id: item.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help(AgentText.t("从收纳中移除", "Remove from shelf"))
            .accessibilityLabel(AgentText.t("移除 \(item.title)", "Remove \(item.title)"))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func kindTitle(_ kind: BubbleShelfItem.Kind) -> String {
        switch kind {
        case .file: AgentText.t("文件", "File")
        case .folder: AgentText.t("文件夹", "Folder")
        case .text: AgentText.t("文本", "Text")
        case .url: AgentText.t("链接", "Link")
        case .image: AgentText.t("图像", "Image")
        }
    }
}

private struct BubbleShelfArtwork: View {
    let item: BubbleShelfItem
    @ObservedObject var store: BubbleShelfStore
    let size: CGFloat

    var body: some View {
        Group {
            if let thumbnail = store.thumbnail(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.075))
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(item.availability == .available ? 0.72 : 0.36))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12), lineWidth: 0.6))
    }

    private var symbol: String {
        switch item.kind {
        case .file: "doc"
        case .folder: "folder"
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        }
    }
}

struct BubbleShelfClosedControl: View {
    let state: BubbleShelfCompactState
    let presentation: BubbleNotchPresentation
    let height: CGFloat
    let widgetWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Group {
            switch presentation {
            case .widget:
                BubbleNotchGlyph(size: widgetWidth, itemCount: state.itemCount, isReceiving: state.isReceiving)
                    .frame(width: widgetWidth, height: height)
            case .minimal:
                let scale = BubbleNotchLayout.minimalScale(closedHeight: height)
                BubbleMinimalStackGlyph(itemCount: state.itemCount, isReceiving: state.isReceiving)
                    .scaleEffect(scale)
                    .frame(width: BubbleNotchLayout.minimalWidth, height: height)
            }
        }
        .scaleEffect(isHovering && state.itemCount > 0 && !reduceMotion ? 1.06 : 1)
        .brightness(isHovering && state.itemCount > 0 ? 0.045 : 0)
        .shadow(color: .white.opacity(isHovering && state.itemCount > 0 ? 0.16 : 0), radius: 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .overlay {
            BubbleShelfDragHandle(
                writers: state.writers,
                preview: { BubbleDragPreview.mark(itemCount: state.itemCount) },
                click: state.onOpen,
                verticalSwipe: state.onVerticalSwipe,
                horizontalSwipe: state.onHorizontalSwipe,
                hover: { isHovering = $0 }
            )
        }
        .auditNotchModule("bubble", mode: presentation.rawValue)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(state.isReceiving
            ? AgentText.t("等待接收", "Receiving") : AgentText.t("暂停接收", "Receiving paused"))
        .accessibilityValue(AgentText.t("\(state.itemCount) 项", "\(state.itemCount) items"))
        .accessibilityHint(AgentText.t("点击打开收纳；向上滑动开始接收，向下滑动暂停；向左或向右拖动可拖出已保存内容。", "Click to open Shelf. Swipe up to receive or down to pause. Drag sideways to export saved items."))
        .accessibilityAction(.default, state.onOpen)
        .help(AgentText.t("点击打开收纳 · 上滑接收 · 下滑暂停 · 横向拖出", "Click for Shelf · swipe up to receive · swipe down to pause · drag sideways to export"))
    }
}

enum BubbleNotchPresentation: String { case widget, minimal }

struct BubbleShelfCompanion: View {
    let state: BubbleShelfCompactState
    let height: CGFloat
    let widgetWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            BubbleShelfClosedControl(state: state, presentation: .minimal, height: height, widgetWidth: widgetWidth)
                .frame(width: 16, height: height)
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: min(14, max(8, height * 0.45)))
                .frame(width: 10, height: height)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
    }
}

/// A compact audio mark for the shared left wing: album art above a short live
/// spectrum. It intentionally occupies the same divider-plus-16pt footprint as
/// the Shelf minimal companion.
struct BubbleShelfAudioMinimal: View {
    let height: CGFloat
    let widgetWidth: CGFloat
    let onOpen: () -> Void
    @ObservedObject private var music = MusicManager.shared

    private var markSize: CGFloat { min(14, max(10, widgetWidth * 0.7)) }

    var body: some View {
        let spectrumWidth = min(13, max(10, widgetWidth * 0.7))
        let spectrumHeight = max(4, min(7, height * 0.22))
        let spectrumScale = min(spectrumWidth / 16, spectrumHeight / 14)
        HStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: min(14, max(8, height * 0.45)))
                .frame(width: 10, height: height)
            Button(action: onOpen) {
                VStack(spacing: 1) {
                    Image(nsImage: music.albumArt)
                        .resizable()
                        .scaledToFill()
                        .frame(width: markSize, height: markSize)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    AudioSpectrumView(isPlaying: $music.isPlaying)
                        // MusicVisualizer draws its bars in a fixed 16×14
                        // layer. Scale that source frame uniformly before
                        // placing it in the compact row; a smaller SwiftUI
                        // frame alone would not clip the AppKit paths.
                        .frame(width: 16, height: 14)
                        .scaleEffect(spectrumScale)
                        .frame(width: spectrumWidth, height: spectrumHeight)
                }
                .frame(width: 16, height: height, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .auditNotchFrame("album")
            .accessibilityLabel(AgentText.t("音乐", "Music"))
        }
        .frame(width: 26, height: height)
        .auditNotchModule("music", mode: "minimal")
    }
}

/// The normal single-slot audio control used beside a compact Shelf mark.
/// The whole album remains the existing click target while a small spectrum
/// keeps playback state visible without restoring the old second right wing.
struct BubbleShelfAudioWidget: View {
    let height: CGFloat
    let widgetWidth: CGFloat
    let onOpen: () -> Void
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        let spectrumWidth = min(10, max(7, widgetWidth * 0.42))
        let spectrumHeight: CGFloat = 8
        let spectrumScale = min(spectrumWidth / 16, spectrumHeight / 14)
        Button(action: onOpen) {
            Image(nsImage: music.albumArt)
                .resizable()
                .scaledToFill()
                .frame(width: widgetWidth, height: widgetWidth)
                .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
                .overlay(alignment: .bottomTrailing) {
                    AudioSpectrumView(isPlaying: $music.isPlaying)
                        .frame(width: 16, height: 14)
                        .scaleEffect(spectrumScale)
                        .frame(width: spectrumWidth, height: spectrumHeight)
                        .padding(1)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 2))
                        .allowsHitTesting(false)
                }
                .frame(width: widgetWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .auditNotchModule("music")
        .auditNotchFrame("album")
        .accessibilityLabel(AgentText.t("音乐", "Music"))
    }
}

/// Shelf-first pair with a fixed `widget + minimal` width in either order.
struct BubbleShelfAudioPair: View {
    let shelf: BubbleShelfCompactState
    let arrangement: BubbleShelfAudioArrangement
    let height: CGFloat
    let widgetWidth: CGFloat
    let onAudioOpen: () -> Void

    private var shelfWithoutPairScroll: BubbleShelfCompactState {
        BubbleShelfCompactState(itemCount: shelf.itemCount,
                                isReceiving: shelf.isReceiving,
                                onOpen: shelf.onOpen,
                                onVerticalSwipe: shelf.onVerticalSwipe,
                                writers: shelf.writers)
    }

    var body: some View {
        HStack(spacing: 0) {
            switch arrangement {
            case .shelfWidgetAudioMinimal:
                BubbleShelfClosedControl(state: shelfWithoutPairScroll, presentation: .widget,
                                         height: height, widgetWidth: widgetWidth)
                    .frame(width: widgetWidth, height: height)
                BubbleShelfAudioMinimal(height: height, widgetWidth: widgetWidth, onOpen: onAudioOpen)
            case .shelfMinimalAudioWidget:
                BubbleShelfCompanion(state: shelfWithoutPairScroll, height: height, widgetWidth: widgetWidth)
                BubbleShelfAudioWidget(height: height, widgetWidth: widgetWidth, onOpen: onAudioOpen)
            }
        }
        .frame(height: height)
        // A local scroll monitor covers the entire pair while returning the
        // original event to the underlying SwiftUI Buttons. Thus horizontal
        // scrolling can swap either side, without swallowing audio clicks or
        // turning mouse drags into layout switches.
        .background(BubbleShelfHorizontalScrollMonitor(onSwipe: shelf.onHorizontalSwipe))
    }
}

private struct BubbleShelfHorizontalScrollMonitor: NSViewRepresentable {
    let onSwipe: (Bool) -> Void

    func makeNSView(context: Context) -> BubbleShelfHorizontalScrollView {
        let view = BubbleShelfHorizontalScrollView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: BubbleShelfHorizontalScrollView, context: Context) {
        view.onSwipe = onSwipe
    }
}

final class BubbleShelfHorizontalScrollView: NSView {
    var onSwipe: ((Bool) -> Void)?
    private var monitor: Any?
    private var lastClaimTimestamp: TimeInterval = 0
    private var lastVerticalClaimTimestamp: TimeInterval = 0
    private var lastEventTimestamp: TimeInterval?
    private var gesture = BubbleHorizontalScrollState()
    private var verticalGesture = BubbleScrollGestureState()
    private var axisLock = BubbleShelfPairScrollAxisLock()

    var hasLocalMonitorForPreview: Bool { monitor != nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { removeMonitor() } else { installMonitor() }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window else { return event }
            let phase = Self.scrollPhase(for: event)
            guard let eventWindow = event.window, eventWindow === window else {
                if phase == .began || phase == .ended { self.resetGesture() }
                return event
            }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else {
                if phase == .began || phase == .ended { self.resetGesture() }
                return event
            }
            let consumed = self.processScroll(deltaX: event.scrollingDeltaX,
                                               deltaY: event.scrollingDeltaY,
                                               phase: phase,
                                               isMomentum: !event.momentumPhase.isEmpty,
                                               timestamp: event.timestamp)
            return consumed ? nil : event
        }
    }

    private static func scrollPhase(for event: NSEvent) -> BubbleScrollPhase {
        if event.phase.isEmpty { return .none }
        if event.phase.contains(.began) { return .began }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
        return .changed
    }

    private func resetGesture() {
        _ = gesture.update(deltaX: 0, deltaY: 0, phase: .ended,
                           isMomentum: false, timestamp: lastEventTimestamp ?? 0,
                           lastClaimTimestamp: lastClaimTimestamp)
        _ = verticalGesture.update(deltaX: 0, deltaY: 0, phase: .ended,
                                   isMomentum: false, timestamp: lastEventTimestamp ?? 0,
                                   lastClaimTimestamp: lastVerticalClaimTimestamp)
        axisLock.reset()
        lastEventTimestamp = nil
    }

    /// Routes one scroll sample for both the AppKit monitor and settings
    /// preview. The outer monitor consumes a horizontal gesture after its
    /// claim, while a vertical claim is passed through to the inner Shelf
    /// receiver so its existing receive toggle still fires.
    @discardableResult
    func processScroll(deltaX: CGFloat, deltaY: CGFloat, phase: BubbleScrollPhase,
                       isMomentum: Bool, timestamp: TimeInterval) -> Bool {
        if phase == .began {
            // A new trackpad gesture is authoritative even when the previous
            // gesture's end sample was outside this view's bounds.
            resetGesture()
        }
        if phase == .ended {
            resetGesture()
            // Deliver the end sample so BubbleInteractionView can clear its
            // own accumulator. It never fires an action for `.ended`.
            return false
        }

        if phase == .none,
           let lastEventTimestamp,
           timestamp - lastEventTimestamp >= 0.45 {
            resetGesture()
        }
        self.lastEventTimestamp = timestamp

        switch axisLock.axis {
        case .horizontal:
            // Once the outer pair has swapped, keep the diagonal tail away
            // from BubbleInteractionView until the gesture ends.
            return true
        case .vertical:
            // The inner receiver must see vertical samples, but a later
            // horizontal tail cannot start a second action.
            return BubbleHorizontalScrollPolicy.isDominantHorizontal(deltaX: deltaX, deltaY: deltaY)
        case nil:
            break
        }

        guard !isMomentum else { return false }
        if BubbleHorizontalScrollPolicy.isDominantHorizontal(deltaX: deltaX, deltaY: deltaY) {
            if let towardLeft = gesture.update(deltaX: deltaX, deltaY: deltaY, phase: phase,
                                               isMomentum: false, timestamp: timestamp,
                                               lastClaimTimestamp: lastClaimTimestamp) {
                axisLock.claim(.horizontal)
                lastClaimTimestamp = timestamp
                onSwipe?(towardLeft)
                return true
            }
            return false
        }
        guard BubbleScrollPolicy.isDominantVertical(deltaX: deltaX, deltaY: deltaY) else {
            return false
        }
        if verticalGesture.update(deltaX: deltaX, deltaY: deltaY, phase: phase,
                                  isMomentum: false, timestamp: timestamp,
                                  lastClaimTimestamp: lastVerticalClaimTimestamp) != nil {
            axisLock.claim(.vertical)
            lastVerticalClaimTimestamp = timestamp
        }
        return false
    }

    /// Settings-preview hook that drives the same reducer as the AppKit local
    /// monitor without posting synthetic global events or requiring a desktop
    /// input permission.
    @discardableResult
    func processPreviewScroll(deltaX: CGFloat, deltaY: CGFloat, phase: BubbleScrollPhase,
                              isMomentum: Bool = false, timestamp: TimeInterval) -> Bool {
        processScroll(deltaX: deltaX, deltaY: deltaY, phase: phase,
                      isMomentum: isMomentum, timestamp: timestamp)
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        resetGesture()
    }

    // Deinitializers are nonisolated in Swift 6; remove the AppKit observer
    // directly, matching the other local event bridges in this target.
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

struct BubbleNotchGlyph: View {
    let size: CGFloat
    let itemCount: Int
    let isReceiving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isReceiving)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            drawing(time: elapsed)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func drawing(time: TimeInterval) -> some View {
        let frontDiameter = size * 0.78
        let frontCenter = CGPoint(x: size * 0.59, y: size * 0.59)
        let rearDiameter = size * 0.54
        let rearCenter = CGPoint(x: size * 0.34, y: size * 0.38)
        let contour = max(0.42, size * 0.026)
        ZStack {
            Circle()
                .fill(Color.black)
                .overlay(Circle().stroke(Color(white: 0.56).opacity(0.48), lineWidth: contour * 0.88))
                .frame(width: rearDiameter, height: rearDiameter)
                .position(rearCenter)

            Circle().fill(Color.black).frame(width: frontDiameter, height: frontDiameter).position(frontCenter)

            BubbleRectangleStack(itemCount: itemCount, size: frontDiameter)
                .frame(width: frontDiameter, height: frontDiameter)
                .clipShape(Circle())
                .position(frontCenter)

            if isReceiving && !reduceMotion {
                BubbleReceiveArc(size: frontDiameter, time: time)
                    .frame(width: frontDiameter, height: frontDiameter)
                    .clipShape(Circle())
                    .position(frontCenter)
            }

            Circle()
                .stroke(Color(white: 0.65).opacity(0.92), lineWidth: contour)
                .frame(width: frontDiameter, height: frontDiameter)
                .position(frontCenter)
        }
        .frame(width: size, height: size)
    }
}

private struct BubbleMinimalStackGlyph: View {
    let itemCount: Int
    let isReceiving: Bool

    var body: some View {
        VStack(spacing: BubbleNotchLayout.minimalGap) {
            BubbleMinimalRectangleStack(itemCount: itemCount)
                .frame(width: BubbleNotchLayout.minimalWidth, height: BubbleNotchLayout.minimalFilesHeight)
            BubbleNotchGlyph(size: BubbleNotchLayout.minimalBubbleDiameter,
                             itemCount: 0, isReceiving: isReceiving)
                .frame(width: BubbleNotchLayout.minimalBubbleDiameter,
                       height: BubbleNotchLayout.minimalBubbleDiameter)
        }
        .frame(width: BubbleNotchLayout.minimalWidth, height: BubbleNotchLayout.minimalTotalHeight)
        .accessibilityHidden(true)
    }
}

private struct BubbleRectangleStack: View {
    let itemCount: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(BubbleNotchLayout.rectangles(for: itemCount)) { page in
                RoundedRectangle(cornerRadius: max(0.35, size * 0.018), style: .continuous)
                    .fill(Color(white: 0.78).opacity(page.opacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: max(0.35, size * 0.018), style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: max(0.30, size * 0.008))
                    }
                    .frame(width: size * page.width, height: size * page.height)
                    .rotationEffect(.degrees(page.rotation))
                    .position(x: size * page.x, y: size * page.y)
                    .zIndex(page.depth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BubbleMinimalRectangleStack: View {
    let itemCount: Int

    var body: some View {
        GeometryReader { geometry in
            let placements = BubbleNotchLayout.minimalPlacements(for: itemCount,
                                                                  width: geometry.size.width,
                                                                  height: geometry.size.height)
            ForEach(placements) { page in
                RoundedRectangle(cornerRadius: max(0.3, min(geometry.size.width, geometry.size.height) * 0.025), style: .continuous)
                    .fill(Color(white: 0.78).opacity(page.opacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: max(0.3, min(geometry.size.width, geometry.size.height) * 0.025), style: .continuous)
                            .strokeBorder(.white.opacity(0.32), lineWidth: 0.35)
                    }
                    .frame(width: page.width, height: page.height)
                    .rotationEffect(.degrees(page.rotation))
                    .position(x: page.x, y: page.y)
                    .zIndex(page.depth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BubbleReceiveArc: View {
    let size: CGFloat
    let time: TimeInterval

    private var speedProgress: Double { BubbleReceiveMotion.speedProgress(at: time) }
    private var lineWidth: CGFloat { max(0.46, size * (0.026 + 0.010 * speedProgress)) }
    private var brightness: Double { 0.50 + 0.48 * speedProgress }
    private var haloRadius: CGFloat { max(0.55, size * (0.025 + 0.020 * speedProgress)) }

    var body: some View {
        BubbleInnerArc(angle: BubbleReceiveMotion.angle(at: time), span: BubbleReceiveMotion.arcSpan,
                       radiusFraction: BubbleReceiveMotion.orbitRadiusFraction)
            .stroke(Color.white.opacity(brightness), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .shadow(color: .white.opacity(0.14 + 0.52 * speedProgress), radius: haloRadius)
    }
}

private struct BubbleInnerArc: Shape {
    var angle: Double
    var span: Double
    var radiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: diameter * radiusFraction,
                    startAngle: .radians(angle - span * 0.5), endAngle: .radians(angle + span * 0.5), clockwise: false)
        return path
    }
}

private struct BubbleShelfDragHandle: NSViewRepresentable {
    var writers: () -> [NSPasteboardWriting]
    var preview: () -> NSImage? = { nil }
    var click: (() -> Void)? = nil
    var verticalSwipe: ((Bool) -> Void)? = nil
    var horizontalSwipe: ((Bool) -> Void)? = nil
    var hover: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> BubbleInteractionView {
        let view = BubbleInteractionView()
        configure(view)
        return view
    }

    func updateNSView(_ view: BubbleInteractionView, context: Context) { configure(view) }

    private func configure(_ view: BubbleInteractionView) {
        view.writers = writers
        view.preview = preview
        view.activate = click
        view.swipe = verticalSwipe
        view.horizontalSwipe = horizontalSwipe
        view.hover = hover
    }
}

@MainActor
private final class BubbleInteractionView: NSView, NSDraggingSource {
    var writers: (() -> [NSPasteboardWriting])?
    var preview: (() -> NSImage?)?
    var activate: (() -> Void)?
    var swipe: ((Bool) -> Void)?
    var horizontalSwipe: ((Bool) -> Void)?
    var hover: ((Bool) -> Void)?
    private var downPoint: NSPoint?
    private var state: Interaction = .idle
    private var lastVerticalToggle: TimeInterval = 0
    private var lastHorizontalToggle: TimeInterval = 0
    private var verticalGesture = BubbleScrollGestureState()
    private var horizontalGesture = BubbleHorizontalScrollState()

    private enum Interaction { case idle, tracking, dragging }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        state = .tracking
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, state == .tracking else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - downPoint.x
        let dy = point.y - downPoint.y
        if hypot(dx, dy) >= 8 {
            state = .dragging
            let payloads = writers?() ?? []
            guard !payloads.isEmpty else { return }
            let dragItems = payloads.enumerated().map { index, payload -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: payload)
                let inset = CGFloat(index % 4) * 1.5
                item.setDraggingFrame(bounds.offsetBy(dx: inset, dy: inset), contents: preview?())
                return item
            }
            beginDraggingSession(with: dragItems, event: event, source: self)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let vertical = event.scrollingDeltaY
        // A wheel usually reports phase `.none`; a trackpad can begin with a zero
        // delta and deliver the useful movement in `.changed`. Accumulate a
        // dominant vertical axis until it reaches the gesture threshold, then
        // claim that gesture once. Momentum is deliberately ignored.
        let phase: BubbleScrollPhase
        if event.phase.isEmpty { phase = .none }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.ended) || event.phase.contains(.cancelled) { phase = .ended }
        else { phase = .changed }
        if phase == .ended {
            _ = verticalGesture.update(deltaX: 0, deltaY: 0, phase: .ended,
                                       isMomentum: false, timestamp: event.timestamp,
                                       lastClaimTimestamp: lastVerticalToggle)
            _ = horizontalGesture.update(deltaX: 0, deltaY: 0, phase: .ended,
                                         isMomentum: false, timestamp: event.timestamp,
                                         lastClaimTimestamp: lastHorizontalToggle)
            super.scrollWheel(with: event)
            return
        }
        guard event.momentumPhase.isEmpty else {
            super.scrollWheel(with: event)
            return
        }
        if BubbleHorizontalScrollPolicy.isDominantHorizontal(deltaX: event.scrollingDeltaX, deltaY: vertical) {
            if let towardLeft = horizontalGesture.update(deltaX: event.scrollingDeltaX, deltaY: vertical,
                                                         phase: phase, isMomentum: false,
                                                         timestamp: event.timestamp,
                                                         lastClaimTimestamp: lastHorizontalToggle) {
                lastHorizontalToggle = event.timestamp
                horizontalSwipe?(towardLeft)
            }
            return
        }
        guard BubbleScrollPolicy.isDominantVertical(deltaX: event.scrollingDeltaX, deltaY: vertical) else {
            super.scrollWheel(with: event)
            return
        }
        if let upward = verticalGesture.update(deltaX: event.scrollingDeltaX, deltaY: vertical,
                                               phase: phase, isMomentum: false,
                                               timestamp: event.timestamp, lastClaimTimestamp: lastVerticalToggle) {
            lastVerticalToggle = event.timestamp
            swipe?(upward)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil; state = .idle }
        switch state {
        case .tracking: activate?()
        case .idle, .dragging: break
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

@MainActor
private struct BubbleShelfDropTarget: NSViewRepresentable {
    let onImport: (BubbleShelfImportResult) -> Void

    func makeNSView(context: Context) -> BubbleShelfDropView {
        let view = BubbleShelfDropView()
        view.onImport = onImport
        view.registerForDraggedTypes([.fileURL, .URL, .string, .tiff, NSPasteboard.PasteboardType("public.png"), NSPasteboard.PasteboardType("com.adobe.pdf")])
        return view
    }

    func updateNSView(_ view: BubbleShelfDropView, context: Context) { view.onImport = onImport }

    @MainActor final class BubbleShelfDropView: NSView {
        var onImport: ((BubbleShelfImportResult) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let result = BubbleShelfStore.shared.importPasteboardManually(sender.draggingPasteboard)
            onImport?(result)
            return result.succeeded
        }
    }
}

private enum BubbleDragPreview {
    static func mark(itemCount: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        defer { image.unlockFocus() }
        let rect = NSRect(x: 1, y: 1, width: 38, height: 38)
        NSColor(calibratedWhite: 0.08, alpha: 0.94).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let rear = NSRect(x: 7, y: 7, width: 21, height: 21)
        NSColor(calibratedWhite: 0.72, alpha: 0.40).setStroke()
        let rearPath = NSBezierPath(ovalIn: rear)
        rearPath.lineWidth = 0.8
        rearPath.stroke()
        let front = NSRect(x: 9, y: 9, width: 29, height: 29)
        NSColor(calibratedWhite: 0.06, alpha: 0.98).setFill()
        NSBezierPath(ovalIn: front).fill()
        for placement in BubbleNotchLayout.rectangles(for: itemCount) {
            let width = 29 * placement.width
            let height = 29 * placement.height
            let card = NSRect(x: 9 + 29 * placement.x - width / 2,
                              y: 9 + 29 * placement.y - height / 2,
                              width: width, height: height)
            NSColor(calibratedWhite: 0.82, alpha: placement.opacity).setFill()
            let path = NSBezierPath(roundedRect: card, xRadius: 0.8, yRadius: 0.8)
            path.fill()
        }
        NSColor(calibratedWhite: 0.88, alpha: 0.9).setStroke()
        let frontPath = NSBezierPath(ovalIn: front)
        frontPath.lineWidth = 1
        frontPath.stroke()
        return image
    }
}
