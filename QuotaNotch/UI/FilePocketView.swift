// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Darwin
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct PocketPouchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 10, y: r.minY + 4))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 10, y: r.minY + 4), control: CGPoint(x: r.midX, y: r.minY + 14))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 16), control: CGPoint(x: r.maxX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX - 1, y: r.maxY - 8), control2: CGPoint(x: r.maxX - 16, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + 16), control1: CGPoint(x: r.minX + 16, y: r.maxY), control2: CGPoint(x: r.minX + 1, y: r.maxY - 8))
        p.addQuadCurve(to: CGPoint(x: r.minX + 10, y: r.minY + 4), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath(); return p
    }
}

struct PocketSectorShape: Shape {
    let angle: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), outer = min(rect.width, rect.height) / 2 - 2, inner = outer - 56
        var points: [CGPoint] = []
        for index in 0...24 {
            let a: Double = (angle - 17 + Double(index) * 34 / 24) * .pi / 180
            points.append(CGPoint(x: center.x + outer * CGFloat(Darwin.cos(a)), y: center.y + outer * CGFloat(Darwin.sin(a))))
        }
        for index in (0...24).reversed() {
            let a: Double = (angle - 17 + Double(index) * 34 / 24) * .pi / 180
            points.append(CGPoint(x: center.x + inner * CGFloat(Darwin.cos(a)), y: center.y + inner * CGFloat(Darwin.sin(a))))
        }
        func near(_ point: CGPoint, _ other: CGPoint, _ amount: CGFloat) -> CGPoint {
            let dx = other.x - point.x, dy = other.y - point.y, d = max(0.001, hypot(dx, dy)), t = min(0.48, amount / d)
            return CGPoint(x: point.x + dx * t, y: point.y + dy * t)
        }
        var path = Path()
        for i in points.indices {
            let point = points[i], rounding: CGFloat = [0, 24, 25, 49].contains(i) ? 7 : 0.2
            let before = near(point, points[(i + points.count - 1) % points.count], rounding)
            let after = near(point, points[(i + 1) % points.count], rounding)
            if i == 0 { path.move(to: before) } else { path.addLine(to: before) }
            path.addQuadCurve(to: after, control: point)
        }
        path.closeSubpath(); return path
    }
}

private struct PocketVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow
        view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PocketGlass<S: Shape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
            else {
                #if compiler(>=6.2)
                if #available(macOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
                else { fallback }
                #else
                fallback
                #endif
            }
        }
        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
    }
    private var fallback: some View {
        PocketVisualEffect().clipShape(shape)
            .overlay(shape.fill(.white.opacity(0.055)))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
    }
}

/// The custom silhouette bends with the pointer; the system supplies the glass.
/// Keeping geometry separate also provides the same gesture on macOS 15/26.
private struct PocketGlassControl<S: Shape, Content: View>: View {
    let shape: S
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag = CGSize.zero
    @State private var pressed = false
    @State private var hoverPoint = CGPoint(x: 18, y: 12)
    @State private var hovering = false
    @State private var suppressClick = false
    var body: some View {
        Button {
            if !suppressClick && hypot(drag.width, drag.height) < 5 { action() }
        } label: {
            content()
                .background(PocketGlass(shape: shape))
                .overlay {
                    if hovering || pressed {
                        RadialGradient(colors: [.white.opacity(pressed ? 0.32 : 0.15), .clear], center: .center, startRadius: 0, endRadius: 65)
                            .frame(width: 130, height: 130).position(hoverPoint)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(x: reduceMotion ? 1 : 1 + (pressed ? 0.025 : 0) + abs(drag.width) / 900,
                     y: reduceMotion ? 1 : 1 + (pressed ? 0.025 : 0) + abs(drag.height) / 900)
        .offset(x: reduceMotion ? 0 : 12 * tanh(drag.width / 65), y: reduceMotion ? 0 : 10 * tanh(drag.height / 65))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovering = true; hoverPoint = location
            case .ended: hovering = false
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                pressed = true; drag = value.translation
                if hypot(drag.width, drag.height) > 5 { suppressClick = true }
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.62)) { pressed = false; drag = .zero }
                DispatchQueue.main.async { suppressClick = false }
            })
    }
}

private struct PocketThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit() }
        }
        .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: url) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 68, height: 68), scale: 1, representationTypes: .thumbnail)
            let result: NSImage? = await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                    continuation.resume(returning: representation?.nsImage)
                }
            }
            if !Task.isCancelled { image = result }
        }
    }
}

private struct PocketRowPositions: PreferenceKey {
    static var defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct FilePocketView: View {
    @ObservedObject var store: FilePocketStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewURL: URL?
    @State private var showList = false
    @State private var showRows = false
    @State private var tilted = false
    @State private var poured = false
    @State private var flights: [PocketItem] = []
    @State private var rowPositions: [String: CGPoint] = [:]
    @State private var flightTargets: [String: CGPoint] = [:]
    @State private var motion: Task<Void, Never>?
    @State private var scrollID = UUID()
    @State private var atBottom = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            pocket.position(x: 74, y: 161).zIndex(3)
            if !showList {
                ForEach(Array(PocketImageAction.allCases.enumerated()), id: \.element.id) { index, action in
                    PocketActionControl(store: store, action: action, angle: Double(index - 1) * 40)
                        .frame(width: 276, height: 276).position(x: 174, y: 161)
                }
            }
            if showList {
                fileList.frame(width: 288, height: 274).position(x: 290, y: 219)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                    .zIndex(1)
            }
            ForEach(Array(flights.enumerated()), id: \.element.id) { index, item in
                let target = flightTargets[item.id] ?? CGPoint(x: 176, y: 145 + CGFloat(index) * 46)
                PocketThumbnail(url: item.url)
                    .rotationEffect(.degrees(poured ? 0 : 28)).scaleEffect(poured ? 1 : 0.5)
                    .position(poured ? target : CGPoint(x: 110, y: 154))
                    .opacity(poured ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.84).delay(Double(index) * 0.045), value: poured)
                    .allowsHitTesting(false).zIndex(5)
            }
            footer.frame(width: 408, height: 58).position(x: 230, y: 393)
        }
        .frame(width: FilePocketController.size.width, height: FilePocketController.size.height)
        .coordinateSpace(name: "pocket")
        .onPreferenceChange(PocketRowPositions.self) { rowPositions = $0 }
        .onChange(of: store.expanded) { _, expanded in animateExpansion(expanded) }
        .onAppear { if store.expanded { animateExpansion(true) } }
        .onDisappear { motion?.cancel() }
        .quickLookPreview($previewURL)
    }

    private var pocket: some View {
        VStack(spacing: 8) {
            PocketGlassControl(shape: PocketPouchShape(), action: { store.expanded.toggle() }) {
                ZStack {
                    if !tilted {
                        ForEach(Array(store.items.prefix(3).enumerated()), id: \.element.id) { index, item in
                            PocketThumbnail(url: item.url).rotationEffect(.degrees(Double(index - 1) * 12))
                                .offset(x: CGFloat(index - 1) * 10, y: -29)
                        }
                    }
                    VStack(spacing: 4) {
                        Image(systemName: (store.dropTarget == .pocket) ? "plus" : "tray").font(.system(size: 20, weight: .regular))
                        Text("\(store.items.count)").font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    }.opacity(tilted ? 0 : 1).offset(y: 6)
                }.frame(width: 92, height: 90)
            }
            .rotationEffect(.degrees(tilted ? 78 : 0), anchor: UnitPoint(x: 0.5, y: 0.58))
            .scaleEffect((store.dropTarget == .pocket) ? 1.08 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78), value: tilted)
            .animation(reduceMotion ? nil : .spring(response: 0.25), value: (store.dropTarget == .pocket))
            .accessibilityLabel(PocketText.t("文件兜，\(store.items.count) 个文件", "File pocket, \(store.items.count) files"))
            .help(PocketText.t("点击展开；拖入暂存", "Click to browse; drop to collect"))
            Text(PocketText.t(tilted ? "收回" : "暂存", tilted ? "Close" : "Pocket"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 110, height: 116)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(PocketText.t("暂存文件", "Pocket files")).font(.system(size: 12, weight: .medium))
                Spacer(); Text("\(store.items.count)").foregroundStyle(.secondary).monospacedDigit()
                Button { store.chooseFiles() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).disabled(store.busy)
                    .help(PocketText.t("添加文件", "Add files"))
                Button { store.expanded = false } label: { Image(systemName: "arrow.turn.up.left") }
                    .buttonStyle(.plain).help(PocketText.t("收回", "Close"))
            }.padding(.horizontal, 14).frame(height: 40)
            if store.items.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text(PocketText.t("把文件拖到兜里", "Drop files into the pocket")).font(.callout)
                    Button(PocketText.t("选择文件…", "Choose files…")) { store.chooseFiles() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.items) { row($0) }
                        Color.clear.frame(height: 1).onAppear { atBottom = true }.onDisappear { atBottom = false }
                    }.padding(.horizontal, 10)
                }
                .id(scrollID)
                .mask(alignment: .bottom) {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: atBottom ? 1 : 0.76), .init(color: atBottom ? .black : .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                }
            }
            HStack(spacing: 12) {
                ForEach(PocketImageAction.allCases) { action in
                    Button(PocketText.title(action)) { store.run(action) }.buttonStyle(.plain)
                }
            }.font(.system(size: 11, weight: .medium)).frame(height: 36)
                .disabled(store.busy || store.items.isEmpty)
        }
        .background(PocketGlass(shape: RoundedRectangle(cornerRadius: 22)))
    }

    private func row(_ item: PocketItem) -> some View {
        let outcome = store.outcomes[item.id]
        return HStack(spacing: 8) {
            Button { previewURL = item.url } label: {
                HStack(spacing: 8) {
                    PocketThumbnail(url: item.url)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: PocketRowPositions.self, value: [item.id: CGPoint(x: geometry.frame(in: .named("pocket")).midX, y: geometry.frame(in: .named("pocket")).midY)])
                        })
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).lineLimit(1).truncationMode(.middle).font(.system(size: 12))
                        if let outcome {
                            Text(outcome.detail).font(.system(size: 11)).foregroundStyle(outcome.failed ? Color.orange : Color.secondary).lineLimit(1)
                        } else { Text(item.url.pathExtension.uppercased()).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(outcome?.detail ?? item.name)
            Button { withAnimation { store.remove(item) } } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 32) }
                .buttonStyle(.plain).disabled(store.busy)
                .help(PocketText.t("移出暂存，保留原文件", "Remove from pocket; keep original"))
                .accessibilityLabel(PocketText.t("移出", "Remove") + " " + item.name)
        }
        .frame(height: 46).opacity(showRows ? 1 : 0)
    }

    private var footer: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                if store.busy {
                    ProgressView(value: Double(store.completed), total: Double(max(1, store.total))).frame(width: 90)
                    Text("\(store.completed)/\(store.total)").monospacedDigit()
                    Button(PocketText.t("取消", "Cancel")) { store.cancel() }
                } else {
                    Button { store.chooseFiles() } label: { Label(PocketText.t("添加", "Add"), systemImage: "plus") }
                    if !store.outputs.isEmpty { Button(PocketText.t("查看结果", "Show outputs")) { store.revealOutputs() } }
                }
                Spacer()
                Button { FilePocketController.shared.hide() } label: { Image(systemName: "xmark") }
                    .help(PocketText.t("隐藏文件兜", "Hide file pocket"))
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 12)
            if !store.status.isEmpty { Text(store.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(store.status) }
        }.padding(.vertical, 8)
            .background(PocketGlass(shape: RoundedRectangle(cornerRadius: 16)))
    }

    private func animateExpansion(_ expanded: Bool) {
        motion?.cancel()
        if reduceMotion {
            tilted = expanded; showList = expanded; showRows = expanded; flights = []; return
        }
        motion = Task { @MainActor in
            if expanded {
                scrollID = UUID(); atBottom = false; showRows = false; poured = false; tilted = true
                withAnimation(.easeOut(duration: 0.2)) { showList = true }
                try? await Task.sleep(for: .milliseconds(230))
                guard !Task.isCancelled else { return }
                captureFlights()
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                poured = true
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                showRows = true; flights = []
            } else {
                captureFlights(); poured = true; showRows = false
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                poured = false
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                flights = []
                withAnimation(.easeOut(duration: 0.15)) { showList = false }
                tilted = false
            }
        }
    }

    private func captureFlights() {
        flightTargets = rowPositions
        flights = store.items.filter { item in
            guard let point = rowPositions[item.id] else { return false }
            return point.y >= 120 && point.y < 320
        }
    }
}

private struct PocketActionControl: View {
    @ObservedObject var store: FilePocketStore
    let action: PocketImageAction
    let angle: Double
    private var symbol: String {
        switch action { case .convert: return "arrow.triangle.2.circlepath"; case .compress: return "arrow.down.right.and.arrow.up.left"; case .resize: return "arrow.up.left.and.arrow.down.right" }
    }
    var body: some View {
        PocketGlassControl(shape: PocketSectorShape(angle: angle), action: { store.run(action) }) {
            ZStack(alignment: .topLeading) {
                Color.clear
                VStack(spacing: 5) { Image(systemName: symbol).font(.system(size: 17)); Text(PocketText.title(action)).font(.system(size: 11, weight: .medium)) }
                    .position(x: CGFloat(138 + 106 * Darwin.cos(angle * .pi / 180)), y: CGFloat(138 + 106 * Darwin.sin(angle * .pi / 180)))
            }.frame(width: 276, height: 276)
        }
        .scaleEffect((store.dropTarget == .action(action)) ? 1.035 : 1)
        .animation(.spring(response: 0.24), value: store.dropTarget)
        .disabled(store.busy)
        .accessibilityLabel(PocketText.title(action))
        .help(PocketText.t("拖入直接处理；点击处理兜内文件", "Drop to process incoming and stored files; click to process the pocket"))
    }
}
