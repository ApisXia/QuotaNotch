// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Two complete, unchorded taps. Holding Shift, typing with it, or combining
/// modifiers must not summon a panel while the user is working in another app.
struct PocketShiftGesture {
    private var downAt: TimeInterval?
    private var firstTap: TimeInterval?
    mutating func reset() { downAt = nil; firstTap = nil }
    mutating func update(shift: Bool, otherModifier: Bool, at time: TimeInterval) -> Bool {
        if otherModifier { reset(); return false }
        if shift {
            if downAt == nil { downAt = time }
            return false
        }
        guard let down = downAt else { return false }
        downAt = nil
        guard time >= down, time - down <= 0.3 else { firstTap = nil; return false }
        if let first = firstTap, time >= first, time - first <= 0.45 {
            firstTap = nil
            return true
        }
        firstTap = time
        return false
    }
}

enum PocketFiles {
    static func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
    static func merged(_ stored: [URL], _ incoming: [URL]) -> [URL] {
        var seen = Set<String>()
        return (stored + incoming).filter { url in
            url.isFileURL && seen.insert(canonical(url).path).inserted
        }
    }

    static func outputURL(for source: URL, suffix: String, extension ext: String,
                          exists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> URL {
        let directory = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent + "-" + suffix
        var index = 0
        while true {
            let name = stem + (index == 0 ? "" : "-\(index)") + "." + ext
            let candidate = directory.appendingPathComponent(name)
            if !exists(candidate.path) { return candidate }
            index += 1
        }
    }
}

enum PocketImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png, heic
    var id: String { rawValue }
    var title: String { rawValue == "jpeg" ? "JPEG" : rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var typeIdentifier: String {
        switch self { case .jpeg: return "public.jpeg"; case .png: return "public.png"; case .heic: return "public.heic" }
    }
}

enum PocketImageAction: String, CaseIterable, Identifiable, Sendable {
    case convert, compress, resize
    var id: String { rawValue }
}

struct PocketImageOptions: Sendable {
    var format: PocketImageFormat = .jpeg
    var quality: Double = 0.8
    var longestEdge: Int = 1920
}

struct PocketImageResult: Sendable {
    let source: URL
    let output: URL?
    let inputBytes: Int
    let outputBytes: Int
}

enum PocketImageError: Error, LocalizedError {
    case notImage, multipleFrames, tooLarge, unsupportedEncoder, decode, encode
    var errorDescription: String? {
        switch self {
        case .notImage: return "This file is not a supported image."
        case .multipleFrames: return "Animated and multi-page images are not supported yet."
        case .tooLarge: return "This image exceeds the 80-megapixel processing limit."
        case .unsupportedEncoder: return "The output format is unavailable on this Mac."
        case .decode: return "The image could not be decoded."
        case .encode: return "The image could not be encoded."
        }
    }
}
