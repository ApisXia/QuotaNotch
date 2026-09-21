// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BubbleShelfStore: ObservableObject {
    static let shared = BubbleShelfStore()

    @Published private(set) var items: [BubbleShelfItem] = []
    @Published var isReceiving: Bool {
        didSet { defaults.set(isReceiving, forKey: Self.isReceivingDefaultsKey) }
    }
    @Published private(set) var storageIssue: String?
    @Published private(set) var exportIssue: String?

    /// Compatibility spelling for surfaces that call receive mode "enabled".
    var isEnabled: Bool {
        get { isReceiving }
        set { isReceiving = newValue }
    }

    var hasBeenConfigured: Bool { defaults.object(forKey: Self.isReceivingDefaultsKey) != nil }

    static let isReceivingDefaultsKey = "bubbleShelfReceiving"

    let storageDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let manifestURL: URL
    private let imageDirectory: URL
    private let exportDirectory: URL
    private var thumbnailCache: [UUID: NSImage] = [:]
    private var thumbnailRequests: [UUID: QLThumbnailGenerator.Request] = [:]
    private var thumbnailTokens: [UUID: UUID] = [:]
    private var preserveExistingManifest = false
    private static let maximumPasteboardEntries = 100

    init(storageDirectory: URL? = nil, defaults: UserDefaults? = nil,
         fileManager: FileManager = .default) {
        let resolvedDefaults = defaults ?? Self.defaultDefaults()
        self.defaults = resolvedDefaults
        self.fileManager = fileManager
        let base = storageDirectory ?? Self.defaultStorageDirectory(fileManager: fileManager)
        self.storageDirectory = base
        self.manifestURL = base.appendingPathComponent("manifest.json", isDirectory: false)
        self.imageDirectory = base.appendingPathComponent("images", isDirectory: true)
        self.exportDirectory = base.appendingPathComponent("exports", isDirectory: true)
        self._isReceiving = Published(initialValue: resolvedDefaults.object(forKey: Self.isReceivingDefaultsKey) as? Bool ?? false)
        restore()
        pruneExportCacheAtLaunch()
    }

#if SETTINGS_PREVIEW
    func configurePreview(items: [BubbleShelfItem]) {
        for id in Array(thumbnailRequests.keys) { cancelThumbnail(for: id) }
        thumbnailCache.removeAll()
        self.items = BubbleShelfRules.restoring(items)
    }

    func resetPreview() {
        for id in Array(thumbnailRequests.keys) { cancelThumbnail(for: id) }
        thumbnailCache.removeAll()
        items = []
        exportIssue = nil
        storageIssue = nil
    }

    /// Clears all preview fixtures and returns the shared preview store to an unconfigured,
    /// default-off state without writing a receive preference back to UserDefaults.
    func resetPreviewConfiguration() {
        resetPreview()
        _isReceiving = Published(initialValue: false)
        defaults.removeObject(forKey: Self.isReceivingDefaultsKey)
    }
#endif

    @discardableResult
    func addFile(_ url: URL) -> BubbleShelfImportResult {
        guard url.isFileURL, fileManager.fileExists(atPath: url.path) else {
            return rejected("The selected file or folder is unavailable.")
        }
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey,
                                                               .contentModificationDateKey, .contentTypeKey,
                                                               .localizedNameKey]) else {
            return rejected("The selected file or folder could not be read.")
        }
        let kind: BubbleShelfItem.Kind = values.isDirectory == true ? .folder : .file
        let displayName = values.localizedName.flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
        let item = BubbleShelfItem(kind: kind, title: displayName, resourceURL: url.standardizedFileURL,
                                   bookmarkData: makeBookmark(for: url),
                                   fileSizeBytes: values.fileSize.map(Int64.init),
                                   modifiedAt: values.contentModificationDate,
                                   contentTypeIdentifier: values.contentType?.identifier)
        return insert(item)
    }

    @discardableResult
    func addText(_ text: String) -> BubbleShelfImportResult {
        guard !text.isEmpty else { return rejected("The text item is empty.") }
        guard text.utf8.count <= BubbleShelfRules.maximumTextBytes else {
            return rejected("The text item exceeds the shelf size limit.")
        }
        return insert(BubbleShelfItem(kind: .text, title: Self.textTitle(text), text: text))
    }

    @discardableResult
    func addURL(_ url: URL) -> BubbleShelfImportResult {
        guard !url.isFileURL, url.scheme != nil else { return rejected("The URL is not supported.") }
        return insert(BubbleShelfItem(kind: .url, title: url.host ?? url.absoluteString,
                                      resourceURL: url))
    }

    /// Imports the explicit contents of a pasteboard snapshot. The shelf never polls the global clipboard.
    @discardableResult
    func importPasteboard(_ pasteboard: NSPasteboard) -> BubbleShelfImportResult {
        guard isReceiving else { return rejected("Receive mode is paused.") }
        return importPasteboardContents(pasteboard)
    }

    /// Imports a user-dropped pasteboard even when automatic receive mode is paused.
    @discardableResult
    func importPasteboardManually(_ pasteboard: NSPasteboard) -> BubbleShelfImportResult {
        importPasteboardContents(pasteboard)
    }

    private func importPasteboardContents(_ pasteboard: NSPasteboard) -> BubbleShelfImportResult {
        var result = BubbleShelfImportResult()
        let entries = pasteboard.pasteboardItems ?? []
        guard !entries.isEmpty else {
            for object in pasteboard.readObjects(forClasses: [NSURL.self, NSImage.self, NSString.self], options: nil) ?? [] {
                if let url = object as? URL {
                    merge(url.isFileURL ? addFile(url) : addURL(url), into: &result)
                } else if let image = object as? NSImage {
                    merge(addImage(image), into: &result)
                } else if let text = object as? String {
                    merge(addPasteboardText(text), into: &result)
                }
            }
            if result.addedCount + result.duplicateCount + result.skippedCount == 0 {
                result.reject("The pasteboard contains no supported file, folder, text, URL, or image.")
            }
            return result
        }

        for (index, entry) in entries.enumerated() {
            guard index < Self.maximumPasteboardEntries else {
                result.skippedCount += entries.count - index
                result.errors.append("The pasteboard item limit was reached; remaining items were skipped.")
                break
            }
            if entry.types.contains(where: Self.isFilePromiseType) {
                result.reject("A promised file could not be imported from this pasteboard.")
            } else if let fileURL = Self.fileURL(from: entry) {
                merge(addFile(fileURL), into: &result)
            } else if let webURL = Self.webURL(from: entry) {
                merge(addURL(webURL), into: &result)
            } else if let imageData = Self.imageData(from: entry) {
                merge(addImageData(imageData), into: &result)
            } else if let text = entry.string(forType: .string), !text.isEmpty {
                merge(addPasteboardText(text), into: &result)
            } else {
                result.reject("A pasteboard item used an unsupported format.")
            }
        }
        if result.addedCount + result.duplicateCount + result.skippedCount == 0 {
            result.reject("The pasteboard contains no supported file, folder, text, URL, or image.")
        }
        return result
    }

    func remove(id: UUID) {
        guard let removed = items.first(where: { $0.id == id }) else { return }
        cancelThumbnail(for: id)
        let prior = items
        items = BubbleShelfRules.removing(id, from: items)
        guard persist() else { items = prior; return }
        removeOwnedImage(for: removed)
        thumbnailCache[id] = nil
    }

    func clear() {
        guard !items.isEmpty else { return }
        let prior = items
        for item in prior { cancelThumbnail(for: item.id) }
        items = []
        guard persist() else { items = prior; return }
        for item in prior { removeOwnedImage(for: item) }
        thumbnailCache.removeAll()
    }

    func thumbnail(for item: BubbleShelfItem) -> NSImage? {
        guard item.availability == .available else { return nil }
        if let cached = thumbnailCache[item.id] { return cached }
        switch item.kind {
        case .image:
            guard let filename = safeImageFilename(item.cachedImageFilename) else { return nil }
            let imageURL = imageDirectory.appendingPathComponent(filename, isDirectory: false)
            guard let image = NSImage(contentsOf: imageURL) else { return nil }
            thumbnailCache[item.id] = image
            return image
        case .file, .folder:
            guard let url = resolvedFileURL(for: item) else { return nil }
            startThumbnailRequest(for: item, at: url)
            return NSWorkspace.shared.icon(forFile: url.path)
        case .text, .url:
            return nil
        }
    }

    /// Resolves a stored bookmark and rechecks the original path before drag export.
    func resolvedFileURL(for item: BubbleShelfItem) -> URL? {
        guard let pathURL = item.fileURL else { return nil }
        if let bookmark = item.bookmarkData, let resolved = resolveBookmark(bookmark) {
            let didStart = resolved.url.startAccessingSecurityScopedResource()
            defer { if didStart { resolved.url.stopAccessingSecurityScopedResource() } }
            if fileManager.fileExists(atPath: resolved.url.path) {
                let refreshedBookmark = resolved.stale ? makeBookmark(for: resolved.url) ?? bookmark : bookmark
                refreshFileReference(id: item.id, url: resolved.url, bookmark: refreshedBookmark)
                return resolved.url
            }
        }
        if fileManager.fileExists(atPath: pathURL.path) {
            refreshFileReference(id: item.id, url: pathURL,
                                 bookmark: makeBookmark(for: pathURL) ?? item.bookmarkData)
            return pathURL
        }
        markUnavailable(item.id)
        return nil
    }

    /// Produces one native pasteboard writer per selected shelf item for ordinary multi-item drags.
    func exportItems(_ ids: [UUID]) -> [NSPasteboardWriting] {
        let requested = Set(ids)
        let selected = items.filter { requested.contains($0.id) }
        let foundIDs = Set(selected.map(\.id))
        var unavailable = Set<UUID>()
        var failed = ids.contains(where: { !foundIDs.contains($0) })
        var writers: [NSPasteboardWriting] = []
        for item in selected {
            switch item.kind {
            case .file, .folder:
                guard let url = resolvedFileURL(for: item) else {
                    unavailable.insert(item.id); failed = true; continue
                }
                let didStart = url.startAccessingSecurityScopedResource()
                writers.append(BubbleShelfPasteboardWriter(representations: [
                    .fileURL: url.absoluteString as NSString
                ], cleanup: { if didStart { url.stopAccessingSecurityScopedResource() } }))
            case .text:
                guard let text = item.text,
                      let fileURL = writeExportFile(for: item, extension: "txt", data: Data(text.utf8)) else {
                    failed = true; continue
                }
                writers.append(BubbleShelfPasteboardWriter(representations: [
                    .string: text as NSString,
                    .fileURL: fileURL.absoluteString as NSString
                ]))
            case .url:
                guard let url = item.resourceURL,
                      let data = Self.weblocData(for: url),
                      let fileURL = writeExportFile(for: item, extension: "webloc", data: data) else {
                    failed = true; continue
                }
                writers.append(BubbleShelfPasteboardWriter(representations: [
                    NSPasteboard.PasteboardType("public.url"): url.absoluteString as NSString,
                    .string: url.absoluteString as NSString,
                    .fileURL: fileURL.absoluteString as NSString
                ]))
            case .image:
                guard let filename = safeImageFilename(item.cachedImageFilename) else {
                    unavailable.insert(item.id); failed = true; continue
                }
                let imageURL = imageDirectory.appendingPathComponent(filename, isDirectory: false)
                guard let data = try? Data(contentsOf: imageURL),
                      let fileURL = linkExportFile(for: item, extension: "png", source: imageURL,
                                                   byteCount: data.count) else {
                    unavailable.insert(item.id); failed = true; continue
                }
                writers.append(BubbleShelfPasteboardWriter(representations: [
                    .png: data,
                    .fileURL: fileURL.absoluteString as NSString
                ]))
            }
        }
        if !unavailable.isEmpty {
            items = BubbleShelfRules.markingUnavailable(unavailable, in: items)
            _ = persist()
        }
        exportIssue = failed ? "Some selected shelf items are unavailable or could not be prepared for export." : nil
        return writers
    }

    private func insert(_ candidate: BubbleShelfItem, ownedImageFilename: String? = nil) -> BubbleShelfImportResult {
        let prior = items
        let outcome = BubbleShelfRules.inserting(candidate, into: prior)
        guard outcome.insertion != .rejected else {
            if let ownedImageFilename { removeOwnedImage(filename: ownedImageFilename) }
            return rejected(prior.count >= BubbleShelfRules.maximumItemCount
                            ? "The shelf is full. Remove an item before adding another."
                            : "The item could not be added to the shelf.")
        }
        items = outcome.items
        guard persist() else {
            items = prior
            if let ownedImageFilename { removeOwnedImage(filename: ownedImageFilename) }
            return rejected("The shelf could not save this item.")
        }

        if case let .duplicate(id) = outcome.insertion,
           let oldItem = prior.first(where: { $0.id == id }),
           let updatedItem = items.first(where: { $0.id == id }),
           oldItem.kind == .file || oldItem.kind == .folder,
           oldItem.resourceURL != updatedItem.resourceURL || oldItem.modifiedAt != updatedItem.modifiedAt
                || oldItem.fileSizeBytes != updatedItem.fileSizeBytes {
            cancelThumbnail(for: id)
            thumbnailCache[id] = nil
        }

        let retainedIDs = Set(items.map(\.id))
        for oldItem in prior where !retainedIDs.contains(oldItem.id) {
            cancelThumbnail(for: oldItem.id)
            thumbnailCache[oldItem.id] = nil
            removeOwnedImage(for: oldItem)
        }
        switch outcome.insertion {
        case .added:
            return BubbleShelfImportResult(addedCount: 1)
        case .duplicate:
            if let ownedImageFilename { removeOwnedImage(filename: ownedImageFilename) }
            return BubbleShelfImportResult(duplicateCount: 1)
        case .rejected:
            return rejected("The item could not be added to the shelf.")
        }
    }

    private func addPasteboardText(_ text: String) -> BubbleShelfImportResult {
        if let url = URL(string: text), url.scheme != nil, !url.isFileURL {
            return addURL(url)
        }
        return addText(text)
    }

    private func addImage(_ image: NSImage) -> BubbleShelfImportResult {
        guard let data = Self.pngData(for: image) else { return rejected("The image could not be decoded.") }
        return addImageData(data)
    }

    private func addImageData(_ sourceData: Data) -> BubbleShelfImportResult {
        guard sourceData.count <= BubbleShelfRules.maximumImageBytes else {
            return rejected("The image exceeds the shelf size limit.")
        }
        guard let image = NSImage(data: sourceData), let data = Self.pngData(for: image) else {
            return rejected("The image could not be decoded.")
        }
        guard data.count <= BubbleShelfRules.maximumImageBytes else {
            return rejected("The image exceeds the shelf size limit.")
        }
        let digest = BubbleShelfItem.sha256(data)
        let filename = UUID().uuidString + ".png"
        let item = BubbleShelfItem(kind: .image, title: "Image", cachedImageFilename: filename,
                                   contentDigest: digest, fileSizeBytes: Int64(data.count),
                                   contentTypeIdentifier: UTType.png.identifier)
        if items.contains(where: { $0.deduplicationKey == item.deduplicationKey }) {
            return insert(item)
        }
        guard imageCacheUsage() + Int64(data.count) <= BubbleShelfRules.maximumImageCacheBytes else {
            return rejected("The shelf image cache is full. Remove an image before adding another.")
        }
        guard writeImage(data, filename: filename) else {
            return rejected("The image could not be saved to the shelf.")
        }
        return insert(item, ownedImageFilename: filename)
    }

    private func restore() {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(BubbleShelfManifest.self, from: data)
            guard manifest.version == BubbleShelfManifest.currentVersion else {
                preserveExistingManifest = true
                storageIssue = "The saved shelf uses an unsupported format."
                return
            }
            var restored = BubbleShelfRules.restoring(manifest.items)
            for index in restored.indices {
                switch restored[index].kind {
                case .file, .folder:
                    if let resolved = restoredFile(restored[index]) {
                        restored[index].resourceURL = resolved.url
                        restored[index].availability = .available
                        if let bookmark = resolved.bookmark { restored[index].bookmarkData = bookmark }
                    } else {
                        restored[index].availability = .unavailable
                    }
                case .image:
                    let filename = safeImageFilename(restored[index].cachedImageFilename)
                    let exists = filename.map { fileManager.fileExists(atPath: imageDirectory.appendingPathComponent($0).path) } ?? false
                    restored[index].availability = exists ? .available : .unavailable
                case .text, .url:
                    restored[index].availability = .available
                }
            }
            items = restored
            if manifest.items != restored { _ = persist() }
            pruneUnreferencedOwnedImages()
        } catch {
            preserveExistingManifest = true
            storageIssue = "The saved shelf could not be read."
        }
    }

    private func restoredFile(_ item: BubbleShelfItem) -> (url: URL, bookmark: Data?)? {
        if let bookmark = item.bookmarkData, let resolved = resolveBookmark(bookmark) {
            let didStart = resolved.url.startAccessingSecurityScopedResource()
            defer { if didStart { resolved.url.stopAccessingSecurityScopedResource() } }
            guard fileManager.fileExists(atPath: resolved.url.path) else { return nil }
            return (resolved.url, resolved.stale ? makeBookmark(for: resolved.url) ?? bookmark : bookmark)
        }
        guard let url = item.fileURL, fileManager.fileExists(atPath: url.path) else { return nil }
        return (url, makeBookmark(for: url) ?? item.bookmarkData)
    }

    private func resolveBookmark(_ data: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            return (url, stale)
        }
        stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    private func makeBookmark(for url: URL) -> Data? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                                         .contentTypeKey, .localizedNameKey]
        return (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: keys,
                                      relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: keys, relativeTo: nil))
    }

    private func writeImage(_ data: Data, filename: String?) -> Bool {
        guard let filename = safeImageFilename(filename) else { return false }
        do {
            try fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            try data.write(to: imageDirectory.appendingPathComponent(filename), options: .atomic)
            return true
        } catch { return false }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
            if preserveExistingManifest && fileManager.fileExists(atPath: manifestURL.path) {
                let backupName = "manifest-unreadable-\(UUID().uuidString).json"
                let backupURL = storageDirectory.appendingPathComponent(backupName, isDirectory: false)
                try fileManager.moveItem(at: manifestURL, to: backupURL)
                preserveExistingManifest = false
            }
            let data = try JSONEncoder().encode(BubbleShelfManifest(items: items))
            try data.write(to: manifestURL, options: .atomic)
            storageIssue = nil
            return true
        } catch {
            storageIssue = "The shelf could not be saved."
            return false
        }
    }

    private func removeOwnedImage(for item: BubbleShelfItem) {
        removeOwnedImage(filename: item.cachedImageFilename)
    }

    private func removeOwnedImage(filename: String?) {
        guard let filename = safeImageFilename(filename) else { return }
        let url = imageDirectory.appendingPathComponent(filename, isDirectory: false)
        try? fileManager.removeItem(at: url)
    }

    private func pruneUnreferencedOwnedImages() {
        let retained = Set(items.compactMap { safeImageFilename($0.cachedImageFilename) })
        guard let files = try? fileManager.contentsOfDirectory(at: imageDirectory,
                                                               includingPropertiesForKeys: nil) else { return }
        for file in files where !retained.contains(file.lastPathComponent) {
            removeOwnedImage(filename: file.lastPathComponent)
        }
    }

    private func safeImageFilename(_ filename: String?) -> String? {
        guard let filename, !filename.isEmpty,
              URL(fileURLWithPath: filename).lastPathComponent == filename,
              filename.hasSuffix(".png"),
              UUID(uuidString: String(filename.dropLast(4))) != nil else { return nil }
        return filename
    }

    private func imageCacheUsage() -> Int64 {
        items.reduce(into: Int64(0)) { total, item in
            guard let filename = safeImageFilename(item.cachedImageFilename) else { return }
            let url = imageDirectory.appendingPathComponent(filename, isDirectory: false)
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
    }

    private func writeExportFile(for item: BubbleShelfItem, extension fileExtension: String, data: Data) -> URL? {
        let digest = BubbleShelfItem.sha256(data)
        let filename = "\(item.id.uuidString)-\(digest).\(fileExtension)"
        let destination = exportDirectory.appendingPathComponent(filename, isDirectory: false)
        if let existing = try? Data(contentsOf: destination), existing == data { return destination }
        let priorSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard exportCacheUsage() - priorSize + Int64(data.count) <= BubbleShelfRules.maximumExportCacheBytes else { return nil }
        do {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch { return nil }
    }

    private func linkExportFile(for item: BubbleShelfItem, extension fileExtension: String,
                                source: URL, byteCount: Int) -> URL? {
        let filename = "\(item.id.uuidString)-\(item.contentDigest ?? UUID().uuidString).\(fileExtension)"
        let destination = exportDirectory.appendingPathComponent(filename, isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) { return destination }
        guard exportCacheUsage() + Int64(byteCount) <= BubbleShelfRules.maximumExportCacheBytes else { return nil }
        do {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try fileManager.linkItem(at: source, to: destination)
            return destination
        } catch { return nil }
    }

    private func exportCacheUsage() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: exportDirectory,
                                                               includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(into: Int64(0)) { total, file in
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
    }

    private func pruneExportCacheAtLaunch() {
        guard let files = try? fileManager.contentsOfDirectory(at: exportDirectory,
                                                               includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var measured = files.compactMap { file -> (url: URL, size: Int64, date: Date)? in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return (file, Int64(size), values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }
        var total = measured.reduce(Int64(0)) { $0 + $1.size }
        while total > BubbleShelfRules.maximumExportCacheBytes, let oldest = measured.first {
            removeExportFile(oldest.url)
            total -= oldest.size
            measured.removeFirst()
        }
    }

    private func removeExportFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent() == exportDirectory.standardizedFileURL else { return }
        try? fileManager.removeItem(at: standardized)
    }

    private func markUnavailable(_ id: UUID) {
        guard items.contains(where: { $0.id == id && $0.availability != .unavailable }) else { return }
        items = BubbleShelfRules.markingUnavailable([id], in: items)
        _ = persist()
    }

    private func refreshFileReference(id: UUID, url: URL, bookmark: Data?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].availability != .available || items[index].resourceURL != url
                || items[index].bookmarkData != bookmark else { return }
        let oldMetadata = items[index]
        items[index].resourceURL = url.standardizedFileURL
        items[index].bookmarkData = bookmark
        items[index].availability = .available
        if oldMetadata.resourceURL != items[index].resourceURL {
            cancelThumbnail(for: id)
            thumbnailCache[id] = nil
        }
        _ = persist()
    }

    private func startThumbnailRequest(for item: BubbleShelfItem, at url: URL) {
        guard thumbnailRequests[item.id] == nil else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 128, height: 128),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .all)
        let token = UUID()
        thumbnailRequests[item.id] = request
        thumbnailTokens[item.id] = token
        let didStart = url.startAccessingSecurityScopedResource()
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            if didStart { url.stopAccessingSecurityScopedResource() }
            guard let image = representation?.nsImage else {
                Task { @MainActor [weak self] in
                    guard let self, self.thumbnailTokens[item.id] == token else { return }
                    self.thumbnailRequests[item.id] = nil
                    self.thumbnailTokens[item.id] = nil
                }
                return
            }
            Task { @MainActor [weak self] in
                guard let self, self.thumbnailTokens[item.id] == token,
                      self.items.contains(where: { $0.id == item.id && $0.availability == .available }) else { return }
                self.thumbnailCache[item.id] = image
                self.thumbnailRequests[item.id] = nil
                self.thumbnailTokens[item.id] = nil
                self.objectWillChange.send()
            }
        }
    }

    private func cancelThumbnail(for id: UUID) {
        thumbnailTokens[id] = nil
        if let request = thumbnailRequests.removeValue(forKey: id) {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }

    private func merge(_ next: BubbleShelfImportResult, into result: inout BubbleShelfImportResult) {
        result.addedCount += next.addedCount
        result.duplicateCount += next.duplicateCount
        result.skippedCount += next.skippedCount
        result.errors.append(contentsOf: next.errors)
    }

    private func rejected(_ error: String) -> BubbleShelfImportResult {
        var result = BubbleShelfImportResult()
        result.reject(error)
        return result
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL else { return nil }
        return url
    }

    private static func webURL(from item: NSPasteboardItem) -> URL? {
        if let value = item.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = URL(string: value), !url.isFileURL, url.scheme != nil { return url }
        return nil
    }

    private static func imageData(from item: NSPasteboardItem) -> Data? {
        item.data(forType: .png) ?? item.data(forType: .tiff)
    }

    private static func isFilePromiseType(_ type: NSPasteboard.PasteboardType) -> Bool {
        type.rawValue.localizedCaseInsensitiveContains("filepromise")
            || type.rawValue.localizedCaseInsensitiveContains("file-promise")
    }

    private static func pngData(for image: NSImage) -> Data? {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private static func textTitle(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let title = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Text" : String(title.prefix(80))
    }

    private static func weblocData(for url: URL) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
    }

    private static func defaultStorageDirectory(fileManager: FileManager) -> URL {
#if SETTINGS_PREVIEW
        return fileManager.temporaryDirectory.appendingPathComponent(
            "QuotaNotch/BubbleShelf-Preview-\(UUID().uuidString)", isDirectory: true)
#else
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true))
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("QuotaNotch/BubbleShelf", isDirectory: true)
#endif
    }

    private static func defaultDefaults() -> UserDefaults {
#if SETTINGS_PREVIEW
        return previewDefaults
#else
        return .standard
#endif
    }

#if SETTINGS_PREVIEW
    private static let previewDefaults = UserDefaults(suiteName: "QuotaNotch.BubbleShelf.Preview.\(UUID().uuidString)")!
#endif
}

private final class BubbleShelfPasteboardWriter: NSObject, NSPasteboardWriting {
    private let types: [NSPasteboard.PasteboardType]
    private let representations: [NSPasteboard.PasteboardType: Any]
    private let cleanup: (() -> Void)?

    init(representations: [NSPasteboard.PasteboardType: Any], cleanup: (() -> Void)? = nil) {
        self.representations = representations
        self.types = Array(representations.keys).sorted { $0.rawValue < $1.rawValue }
        self.cleanup = cleanup
    }

    deinit { cleanup?() }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { types }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        representations[type]
    }
}
