// SPDX-License-Identifier: GPL-3.0-only
import CryptoKit
import Foundation

struct BubbleShelfItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case file, folder, text, url, image
    }

    enum Availability: String, Codable {
        case available, unavailable
    }

    var id: UUID
    var kind: Kind
    var title: String
    var addedAt: Date
    var text: String?
    var resourceURL: URL?
    var bookmarkData: Data?
    var cachedImageFilename: String?
    var contentDigest: String?
    var availability: Availability
    var fileSizeBytes: Int64?
    var modifiedAt: Date?
    var contentTypeIdentifier: String?

    init(id: UUID = UUID(), kind: Kind, title: String, addedAt: Date = Date(), text: String? = nil,
         resourceURL: URL? = nil, bookmarkData: Data? = nil, cachedImageFilename: String? = nil,
         contentDigest: String? = nil, availability: Availability = .available,
         fileSizeBytes: Int64? = nil, modifiedAt: Date? = nil, contentTypeIdentifier: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.addedAt = addedAt
        self.text = text
        self.resourceURL = resourceURL
        self.bookmarkData = bookmarkData
        self.cachedImageFilename = cachedImageFilename
        self.contentDigest = contentDigest
        self.availability = availability
        self.fileSizeBytes = fileSizeBytes
        self.modifiedAt = modifiedAt
        self.contentTypeIdentifier = contentTypeIdentifier
    }

    var fileURL: URL? {
        guard kind == .file || kind == .folder, resourceURL?.isFileURL == true else { return nil }
        return resourceURL
    }

    var deduplicationKey: String? {
        switch kind {
        case .file, .folder:
            guard let fileURL else { return nil }
            return "resource:" + fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        case .text:
            guard let text else { return nil }
            return "text:" + Self.sha256(Data(text.utf8))
        case .url:
            guard let resourceURL, !resourceURL.isFileURL else { return nil }
            guard var components = URLComponents(url: resourceURL, resolvingAgainstBaseURL: false) else {
                return "url:" + resourceURL.absoluteString
            }
            // Read the optional fields before assigning them back. Swift's
            // exclusivity checker rejects overlapping access when a property
            // is read from and written through the same optional chain.
            let normalizedScheme = components.scheme?.lowercased()
            let normalizedHost = components.host?.lowercased()
            components.scheme = normalizedScheme
            components.host = normalizedHost
            return "url:" + (components.url?.absoluteString ?? resourceURL.absoluteString)
        case .image:
            guard let contentDigest, !contentDigest.isEmpty else { return nil }
            return "image:" + contentDigest.lowercased()
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct BubbleShelfManifest: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var items: [BubbleShelfItem]

    init(version: Int = currentVersion, items: [BubbleShelfItem] = []) {
        self.version = version
        self.items = items
    }
}

struct BubbleShelfImportResult: Equatable {
    var addedCount = 0
    var duplicateCount = 0
    var skippedCount = 0
    var errors: [String] = []

    init(addedCount: Int = 0, duplicateCount: Int = 0, skippedCount: Int = 0, errors: [String] = []) {
        self.addedCount = addedCount
        self.duplicateCount = duplicateCount
        self.skippedCount = skippedCount
        self.errors = errors
    }

    var succeeded: Bool { addedCount > 0 || duplicateCount > 0 }

    var message: String? {
        guard succeeded || skippedCount > 0 || !errors.isEmpty else { return nil }
        var parts: [String] = []
        if addedCount > 0 { parts.append("\(addedCount) added") }
        if duplicateCount > 0 { parts.append("\(duplicateCount) already on the shelf") }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if !errors.isEmpty { parts.append(errors.joined(separator: " ")) }
        return parts.joined(separator: "; ")
    }

    mutating func reject(_ message: String) {
        skippedCount += 1
        errors.append(message)
    }
}

enum BubbleShelfRules {
    static let maximumItemCount = 80
    static let maximumTextBytes = 1_000_000
    static let maximumImageBytes = 16_000_000
    static let maximumImageCacheBytes = 128_000_000
    static let maximumExportCacheBytes = 256_000_000

    enum Insertion: Equatable {
        case added(UUID)
        case duplicate(UUID)
        case rejected
    }

    struct InsertionResult: Equatable {
        var items: [BubbleShelfItem]
        var insertion: Insertion
    }

    static func restoring(_ items: [BubbleShelfItem], maximumItems: Int = maximumItemCount) -> [BubbleShelfItem] {
        guard maximumItems > 0 else { return [] }
        let sorted = items.sorted {
            if $0.addedAt != $1.addedAt { return $0.addedAt > $1.addedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var seen = Set<String>()
        var restored: [BubbleShelfItem] = []
        for item in sorted where isWellFormed(item) {
            guard let key = item.deduplicationKey, seen.insert(key).inserted else { continue }
            restored.append(item)
            if restored.count == maximumItems { break }
        }
        return restored
    }

    static func inserting(_ candidate: BubbleShelfItem, into items: [BubbleShelfItem],
                          maximumItems: Int = maximumItemCount) -> InsertionResult {
        guard maximumItems > 0, isWellFormed(candidate), let key = candidate.deduplicationKey else {
            return InsertionResult(items: restoring(items, maximumItems: maximumItems), insertion: .rejected)
        }

        if let existing = items.first(where: { $0.deduplicationKey == key }) {
            var promoted = existing
            promoted.addedAt = candidate.addedAt
            if candidate.kind == .file || candidate.kind == .folder || candidate.kind == .url {
                promoted.kind = candidate.kind
                promoted.title = candidate.title
                promoted.resourceURL = candidate.resourceURL
                promoted.bookmarkData = candidate.bookmarkData
                promoted.availability = candidate.availability
                promoted.fileSizeBytes = candidate.fileSizeBytes
                promoted.modifiedAt = candidate.modifiedAt
                promoted.contentTypeIdentifier = candidate.contentTypeIdentifier
            }
            let remainder = items.filter { $0.id != existing.id }
            return InsertionResult(items: restoring([promoted] + remainder, maximumItems: maximumItems),
                                   insertion: .duplicate(existing.id))
        }

        guard items.count < maximumItems else {
            return InsertionResult(items: restoring(items, maximumItems: maximumItems), insertion: .rejected)
        }
        let normalized = restoring([candidate] + items, maximumItems: maximumItems)
        guard normalized.contains(where: { $0.id == candidate.id }) else {
            return InsertionResult(items: normalized, insertion: .rejected)
        }
        return InsertionResult(items: normalized, insertion: .added(candidate.id))
    }

    static func removing(_ id: UUID, from items: [BubbleShelfItem]) -> [BubbleShelfItem] {
        items.filter { $0.id != id }
    }

    static func markingUnavailable(_ ids: Set<UUID>, in items: [BubbleShelfItem]) -> [BubbleShelfItem] {
        items.map { item in
            guard ids.contains(item.id) else { return item }
            var updated = item
            updated.availability = .unavailable
            return updated
        }
    }

    private static func isWellFormed(_ item: BubbleShelfItem) -> Bool {
        switch item.kind {
        case .file, .folder:
            return item.fileURL != nil
        case .text:
            guard let text = item.text else { return false }
            return !text.isEmpty && text.utf8.count <= maximumTextBytes
        case .url:
            return item.resourceURL.map { !$0.isFileURL && $0.scheme != nil } ?? false
        case .image:
            guard let filename = item.cachedImageFilename, !filename.isEmpty,
                  !filename.contains("/"), !filename.contains("\\") else { return false }
            return item.contentDigest?.isEmpty == false
        }
    }
}
