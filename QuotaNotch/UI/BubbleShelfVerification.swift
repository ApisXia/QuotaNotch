// SPDX-License-Identifier: GPL-3.0-only
// Preview-only behavioral verification for the persistent Bubble Shelf.
import AppKit
import Combine
import Foundation

#if SETTINGS_PREVIEW
@MainActor
enum BubbleShelfVerification {
    private static let urlType = NSPasteboard.PasteboardType("public.url")

    static func run() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("QuotaNotch-BubbleShelf-Verification-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "QuotaNotch.BubbleShelf.Verification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let store = BubbleShelfStore(storageDirectory: root, defaults: defaults, fileManager: fileManager)
        try check(!store.isReceiving, "Fresh verification storage must start with receiving paused")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("QuotaNotch.BubbleShelf.Verification.\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let fixtureDirectory = root.appendingPathComponent("fixtures", isDirectory: true)
        try fileManager.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fileURL = fixtureDirectory.appendingPathComponent("source.txt")
        let folderURL = fixtureDirectory.appendingPathComponent("Folder", isDirectory: true)
        try Data("Original source".utf8).write(to: fileURL)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let webURL = URL(string: "https://example.com/docs#verification")!
        let imageData = try makePNGData()

        let allItems = [
            pasteboardItem { $0.setString(fileURL.absoluteString, forType: .fileURL) },
            pasteboardItem { $0.setString(folderURL.absoluteString, forType: .fileURL) },
            pasteboardItem { $0.setString("Shelf text", forType: .string) },
            pasteboardItem {
                $0.setString(webURL.absoluteString, forType: urlType)
                $0.setString(webURL.absoluteString, forType: .string)
            },
            pasteboardItem { $0.setData(imageData, forType: .png) }
        ]
        pasteboard.writeObjects(allItems)

        let paused = store.importPasteboard(pasteboard)
        try check(!paused.succeeded && paused.skippedCount == 1, "Automatic import while paused must reject clearly")
        let imported = store.importPasteboardManually(pasteboard)
        try check(imported.succeeded && imported.addedCount == 5 && store.items.count == 5,
                  "Manual import must accept one file, folder, text, URL, and image")

        let textID = try require(store.items.first(where: { $0.kind == .text })?.id, "Text item missing")
        let duplicate = store.addText("Shelf text")
        try check(duplicate.duplicateCount == 1 && duplicate.succeeded,
                  "Duplicate text must report a duplicate without creating a second item")
        try check(store.items.first?.id == textID, "Duplicate promotion must preserve the original stable ID")

        let thumbnailRoot = root.appendingPathComponent("thumbnail-read", isDirectory: true)
        let thumbnailDefaults = UserDefaults(suiteName: "QuotaNotch.BubbleShelf.Thumbnail.\(UUID().uuidString)")!
        let thumbnailStore = BubbleShelfStore(storageDirectory: thumbnailRoot,
                                               defaults: thumbnailDefaults,
                                               fileManager: fileManager)
        let thumbnailPasteboard = NSPasteboard(name: NSPasteboard.Name("QuotaNotch.BubbleShelf.Verification.Thumbnail.\(UUID().uuidString)"))
        thumbnailPasteboard.clearContents()
        let thumbnailImageItem = NSPasteboardItem()
        thumbnailImageItem.setData(imageData, forType: .png)
        thumbnailPasteboard.writeObjects([thumbnailImageItem])
        let thumbnailImageResult = thumbnailStore.importPasteboardManually(thumbnailPasteboard)
        try check(thumbnailImageResult.succeeded, "Thumbnail image fixture could not be added")
        let thumbnailImage = try require(thumbnailStore.items.first(where: { $0.kind == .image }),
                                         "Thumbnail image fixture is missing")
        let unbookmarkedFile = BubbleShelfItem(kind: .file, title: "source.txt", resourceURL: fileURL)
        thumbnailStore.configurePreview(items: [thumbnailImage, unbookmarkedFile])
        let itemsBeforeThumbnailLookup = thumbnailStore.items
        var publishedDuringThumbnailLookup = false
        let thumbnailSubscription = thumbnailStore.objectWillChange.sink { _ in
            publishedDuringThumbnailLookup = true
        }
        _ = thumbnailStore.thumbnail(for: unbookmarkedFile)
        _ = thumbnailStore.thumbnail(for: thumbnailImage)
        thumbnailSubscription.cancel()
        try check(thumbnailStore.items == itemsBeforeThumbnailLookup,
                  "Thumbnail lookup must not mutate stored item metadata")
        try check(!publishedDuringThumbnailLookup,
                  "Thumbnail lookup must not publish synchronously during view evaluation")
        thumbnailStore.resetPreview()
        thumbnailPasteboard.clearContents()

        let unsupportedPasteboard = NSPasteboard(name: NSPasteboard.Name("QuotaNotch.BubbleShelf.Verification.Unsupported.\(UUID().uuidString)"))
        unsupportedPasteboard.clearContents()
        let unsupportedItem = NSPasteboardItem()
        unsupportedItem.setString("opaque", forType: NSPasteboard.PasteboardType("com.example.unsupported"))
        unsupportedPasteboard.writeObjects([unsupportedItem])
        let unsupported = store.importPasteboardManually(unsupportedPasteboard)
        try check(!unsupported.succeeded && unsupported.skippedCount == 1,
                  "Unsupported-only pasteboard must not report success")
        unsupportedPasteboard.clearContents()

        let partialPasteboard = NSPasteboard(name: NSPasteboard.Name("QuotaNotch.BubbleShelf.Verification.Partial.\(UUID().uuidString)"))
        partialPasteboard.clearContents()
        let partialText = NSPasteboardItem()
        partialText.setString("Partial success", forType: .string)
        let partialBad = NSPasteboardItem()
        partialBad.setString("bad", forType: NSPasteboard.PasteboardType("com.example.unsupported"))
        partialPasteboard.writeObjects([partialText, partialBad])
        let partial = store.importPasteboardManually(partialPasteboard)
        try check(partial.addedCount == 1 && partial.skippedCount == 1 && partial.succeeded,
                  "Mixed supported and unsupported pasteboard must report partial success")
        partialPasteboard.clearContents()

        let restored = BubbleShelfStore(storageDirectory: root, defaults: defaults, fileManager: fileManager)
        try check(restored.items.count == store.items.count, "A new store must restore the saved manifest")
        try check(restored.items.contains(where: {
            $0.kind == .folder && $0.availability == .available
                && sameFileLocation($0.fileURL, folderURL)
        }), "Restored store must retain folder references")

        let originalData = try Data(contentsOf: fileURL)
        let fileItem = try require(restored.items.first(where: { $0.kind == .file }), "File item missing")
        restored.remove(id: fileItem.id)
        let originalStillPresent = fileManager.fileExists(atPath: fileURL.path)
            && (try? Data(contentsOf: fileURL)) == originalData
        try check(originalStillPresent,
                  "Removing a shelf item must leave the original file untouched")

        let capacityStore = BubbleShelfStore(storageDirectory: root.appendingPathComponent("capacity"), defaults: UserDefaults(suiteName: "QuotaNotch.BubbleShelf.Capacity.\(UUID().uuidString)")!, fileManager: fileManager)
        for index in 0..<BubbleShelfRules.maximumItemCount {
            let result = capacityStore.addText("capacity-\(index)")
            try check(result.succeeded, "Capacity fixture item \(index) failed to add")
        }
        let oldestID = try require(capacityStore.items.last?.id, "Capacity fixture has no oldest item")
        let overflow = capacityStore.addText("capacity-overflow")
        try check(!overflow.succeeded && capacityStore.items.count == BubbleShelfRules.maximumItemCount,
                  "The shelf cap must reject new content without evicting old content")
        try check(capacityStore.items.contains(where: { $0.id == oldestID }), "Capacity rejection evicted an existing item")

        let missingFile = fixtureDirectory.appendingPathComponent("missing.txt")
        try Data("gone".utf8).write(to: missingFile)
        let missingResult = restored.addFile(missingFile)
        try check(missingResult.succeeded, "Missing-file export fixture could not be added")
        let missingID = try require(restored.items.first(where: {
            sameFileLocation($0.fileURL, missingFile)
        })?.id, "Missing-file item missing")
        try fileManager.removeItem(at: missingFile)
        let missingWriters = restored.exportItems([missingID])
        try check(missingWriters.isEmpty && restored.exportIssue != nil, "Missing-file export must report an unavailable source")
        restored.clear()
        try check(fileManager.fileExists(atPath: folderURL.path) && fileManager.fileExists(atPath: fileURL.path),
                  "Clearing the shelf must leave original files and folders untouched")

        let exportStore = BubbleShelfStore(storageDirectory: root.appendingPathComponent("exports"), defaults: UserDefaults(suiteName: "QuotaNotch.BubbleShelf.Exports.\(UUID().uuidString)")!, fileManager: fileManager)
        _ = exportStore.addText("Export text")
        _ = exportStore.addURL(webURL)
        pasteboard.clearContents()
        let exportImage = NSPasteboardItem()
        exportImage.setData(imageData, forType: .png)
        pasteboard.writeObjects([exportImage])
        _ = exportStore.importPasteboardManually(pasteboard)
        let exportIDs = exportStore.items.map(\.id)
        let writers = exportStore.exportItems(exportIDs)
        try check(writers.count == 3, "Text, URL, and image exports must each produce a writer")
        var fallbackURLs: [URL] = []
        for writer in writers {
            let types = Set(writer.writableTypes(for: pasteboard))
            try check(types.contains(.fileURL), "Every non-file export must have a Finder file fallback")
            if let value = writer.pasteboardPropertyList(forType: .fileURL) as? String,
               let url = URL(string: value) {
                fallbackURLs.append(url)
                try check(fileManager.fileExists(atPath: url.path), "Export fallback file was not created")
                if types.contains(.png) {
                    try check(url.pathExtension == "png", "Image export fallback must be a PNG file")
                } else if types.contains(urlType) {
                    try check(url.pathExtension == "webloc", "URL export fallback must be a Webloc file")
                } else if types.contains(.string) {
                    try check(url.pathExtension == "txt", "Text export fallback must be a text file")
                }
            }
            if types.contains(.string) {
                try check((writer.pasteboardPropertyList(forType: .string) as? String)?.isEmpty == false,
                          "Text/URL export native string representation was not readable")
            }
            if types.contains(urlType) {
                let value = writer.pasteboardPropertyList(forType: urlType) as? String
                let parsedURL = value.flatMap { URL(string: $0) }
                try check(parsedURL?.isFileURL == false,
                          "URL export native URL representation was not readable")
            }
            if types.contains(.png) {
                let data = writer.pasteboardPropertyList(forType: .png) as? Data
                let image = data.flatMap { NSImage(data: $0) }
                try check(image != nil, "PNG representation was not readable")
            }
        }
        try check(exportStore.items.map(\.id) == exportIDs, "Export preparation must not remove shelf source items")
        exportStore.clear()
        for url in fallbackURLs {
            try check(fileManager.fileExists(atPath: url.path) && (try? Data(contentsOf: url))?.isEmpty == false,
                      "Prepared export data must survive shelf clear and drag cancellation")
        }

        let corruptRoot = root.appendingPathComponent("corrupt", isDirectory: true)
        try fileManager.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: corruptRoot.appendingPathComponent("manifest.json"))
        let corruptDefaults = UserDefaults(suiteName: "QuotaNotch.BubbleShelf.Corrupt.\(UUID().uuidString)")!
        let corruptStore = BubbleShelfStore(storageDirectory: corruptRoot, defaults: corruptDefaults, fileManager: fileManager)
        try check(corruptStore.addText("repair").succeeded, "Store could not recover from an unreadable manifest")
        let backups = try fileManager.contentsOfDirectory(at: corruptRoot, includingPropertiesForKeys: nil)
        try check(backups.contains(where: { $0.lastPathComponent.hasPrefix("manifest-unreadable-") }),
                  "Unreadable manifest was not preserved before repair")

        print("Verified Bubble Shelf persistence, paused/manual import, native exports, cap retention, missing sources, and cleanup")
    }

    private static func pasteboardItem(_ fill: (NSPasteboardItem) -> Void) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        fill(item)
        return item
    }

    private static func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw VerificationError("Could not create PNG fixture")
        }
        return data
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw VerificationError(message) }
        return value
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VerificationError(message) }
    }

    private static func sameFileLocation(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs else { return false }
        return lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private struct VerificationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }
}
#endif
