// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum PocketText {
    static func t(_ chinese: String, _ english: String) -> String { AgentText.t(chinese, english) }
    static func title(_ action: PocketImageAction) -> String {
        switch action {
        case .convert: return t("转换", "Convert")
        case .compress: return t("压缩", "Compress")
        case .resize: return t("尺寸", "Resize")
        }
    }
    static func error(_ error: Error) -> String {
        guard let imageError = error as? PocketImageError else { return error.localizedDescription }
        switch imageError {
        case .notImage: return t("暂不支持这种文件；本版只处理图片。", "Unsupported file; this version processes images only.")
        case .multipleFrames: return t("暂不处理动画或多页图片，原文件已保留。", "Animated or multi-page image; original preserved.")
        case .tooLarge: return t("图片超过 8000 万像素处理上限。", "Image exceeds the 80-megapixel limit.")
        case .unsupportedEncoder: return t("当前系统不支持这种输出格式。", "Output format unavailable on this Mac.")
        case .decode: return t("无法读取图片。", "Could not decode image.")
        case .encode: return t("无法生成图片。", "Could not encode image.")
        }
    }
}

struct PocketItem: Identifiable {
    let url: URL
    var id: String { PocketFiles.canonical(url).path }
    var name: String { url.lastPathComponent }
}

struct PocketOutcome {
    let detail: String
    let output: URL?
    let failed: Bool
}

@MainActor
final class FilePocketStore: ObservableObject {
    static let shared = FilePocketStore()
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "filePocketEnabled")
            if !enabled { cancel(); FilePocketController.shared.hide() }
            FilePocketController.shared.refreshMonitoring()
        }
    }
    @Published var format: PocketImageFormat { didSet { defaults.set(format.rawValue, forKey: "filePocketFormat") } }
    @Published var quality: Double { didSet { defaults.set(quality, forKey: "filePocketQuality") } }
    @Published var longestEdge: Int { didSet { defaults.set(longestEdge, forKey: "filePocketLongestEdge") } }
    @Published private(set) var items: [PocketItem] = []
    @Published private(set) var outcomes: [String: PocketOutcome] = [:]
    @Published private(set) var busy = false
    @Published var dropTarget: PocketDropTarget?
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published var expanded = false
    @Published var status = ""
    private let defaults: UserDefaults
    private var job: Task<Void, Never>?
    var outputs: [URL] { outcomes.values.compactMap(\.output) }
    var options: PocketImageOptions { PocketImageOptions(format: format, quality: quality, longestEdge: longestEdge) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "filePocketEnabled")
        format = PocketImageFormat(rawValue: defaults.string(forKey: "filePocketFormat") ?? "") ?? .jpeg
        quality = defaults.object(forKey: "filePocketQuality") == nil ? 0.8 : min(1, max(0.1, defaults.double(forKey: "filePocketQuality")))
        longestEdge = max(64, min(16000, defaults.object(forKey: "filePocketLongestEdge") as? Int ?? 1920))
        let bookmarks = defaults.array(forKey: "filePocketBookmarks") as? [Data] ?? []
        let urls = bookmarks.compactMap { data -> URL? in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        items = PocketFiles.merged([], urls).prefix(300).map { PocketItem(url: $0) }
    }

    func add(_ urls: [URL]) {
        let valid = urls.filter { url in
            guard url.isFileURL else { return false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        let merged = PocketFiles.merged(items.map(\.url), valid)
        items = merged.prefix(300).map { PocketItem(url: $0) }
        persist()
        if merged.count > 300 { status = PocketText.t("最多暂存 300 个文件。", "The pocket holds up to 300 files.") }
        else if valid.count < urls.count { status = PocketText.t("仅接收可读取的本地文件，不包含文件夹。", "Only readable local files are accepted; folders are excluded.") }
        else { status = PocketText.t("已暂存 \(items.count) 个文件", "\(items.count) files in pocket") }
    }

    func remove(_ item: PocketItem) {
        guard !busy else { return }
        items.removeAll { $0.id == item.id }; outcomes.removeValue(forKey: item.id); persist()
    }

    func chooseFiles() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK { add(panel.urls) }
    }

    @discardableResult
    func accept(_ urls: [URL], action: PocketImageAction? = nil) -> Bool {
        guard enabled, !busy, !urls.isEmpty else { return false }
        let snapshot = items.map(\.url), options = self.options
        add(urls)
        let accepted = Set(items.map(\.id))
        let incoming = urls.filter { accepted.contains(PocketFiles.canonical($0).path) }
        guard !incoming.isEmpty else { return false }
        let inputs = PocketFiles.merged(snapshot, incoming)
        if let action { run(action, urls: inputs, options: options) }
        return !inputs.isEmpty
    }

    func run(_ action: PocketImageAction) { run(action, urls: items.map(\.url), options: options) }
    private func run(_ action: PocketImageAction, urls: [URL], options: PocketImageOptions) {
        guard enabled, !busy, !urls.isEmpty else { return }
        let inputs = PocketFiles.merged([], urls)
        busy = true; completed = 0; total = inputs.count; outcomes = [:]; expanded = true
        status = PocketText.t("正在处理…", "Processing…")
        job = Task { [weak self] in
            for url in inputs {
                guard !Task.isCancelled else { break }
                let worker = Task.detached(priority: .userInitiated) { () -> Result<PocketImageResult, Error> in
                    Result { try autoreleasepool { try PocketImageProcessor.process(url, action: action, options: options) } }
                }
                let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
                guard let self else { return }
                let id = PocketFiles.canonical(url).path
                switch result {
                case .success(let value):
                    let detail = value.output == nil
                        ? PocketText.t("已是较小体积，保留原图", "Already smaller; original kept")
                        : ByteCountFormatter.string(fromByteCount: Int64(value.outputBytes), countStyle: .file)
                    self.outcomes[id] = PocketOutcome(detail: detail, output: value.output, failed: false)
                case .failure(let error):
                    if error is CancellationError { break }
                    self.outcomes[id] = PocketOutcome(detail: PocketText.error(error), output: nil, failed: true)
                }
                if !Task.isCancelled { self.completed += 1 }
            }
            guard let self else { return }
            let failed = self.outcomes.values.filter(\.failed).count
            self.status = Task.isCancelled ? PocketText.t("已取消；已生成的文件保留。", "Cancelled; completed outputs are kept.")
                : PocketText.t("已处理 \(self.completed) 个 · \(failed) 个失败", "Processed \(self.completed) · \(failed) failed")
            self.busy = false; self.job = nil
        }
    }

    func cancel() {
        job?.cancel()
    }

    func revealOutputs() { NSWorkspace.shared.activateFileViewerSelecting(outputs) }

    private func persist() {
        let bookmarks = items.compactMap { item -> Data? in
            let access = item.url.startAccessingSecurityScopedResource()
            defer { if access { item.url.stopAccessingSecurityScopedResource() } }
            return try? item.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        defaults.set(bookmarks, forKey: "filePocketBookmarks")
    }
}
