//
//  ArtworkFallback.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//  Adapted from boring.notch (dev), the iTunes artwork fallback in AppleMusicController.
//

import AppKit
import Foundation

/// Album art from the iTunes Search API for tracks whose player sends none: streamed Apple
/// Music tracks, and apps such as QQ Music that report the song to macOS without its cover.
/// One lookup per album; a lookup that finds nothing is remembered so it isn't repeated.
final class ArtworkFallback: @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var artwork: Data?
    private var task: Task<Void, Never>?

    deinit { task?.cancel() }

    /// The cached artwork for this track's album, or nil. When nothing is cached yet, starts a
    /// lookup and calls `deliver` with the artwork and its key if one is found.
    func artwork(title: String, artist: String, album: String,
                 deliver: @escaping @Sendable (_ artwork: Data, _ key: String) -> Void) -> Data? {
        guard let key = Self.key(title: title, artist: artist, album: album) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if key == self.key { return artwork }
        self.key = key
        artwork = nil
        task?.cancel()
        let albumName = Self.clean(album)
        task = Task { [weak self] in
            let result: Data?
            do {
                result = try await Self.lookUp(artist: artist, album: albumName, title: title)
            } catch {
                // A network failure: forget the key so a later update tries again.
                self?.forget(key)
                return
            }
            guard let data = result, !Task.isCancelled, let self, self.store(data, for: key) else { return }
            deliver(data, key)
        }
        return nil
    }

    /// Identifies the artwork: the album, or the track when there is no album.
    static func key(title: String, artist: String, album: String) -> String? {
        let artist = clean(artist), title = clean(title), album = clean(album)
        guard !title.isEmpty, title != "Not Playing", !artist.isEmpty else { return nil }
        return "\(artist)|\(album.isEmpty ? title : album)"
    }

    private func forget(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        if self.key == key { self.key = nil }
    }

    private func store(_ data: Data, for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.key == key else { return false }
        artwork = data
        return true
    }

    private static func clean(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Unknown" ? "" : trimmed
    }

    /// Returns the artwork, nil when nothing matching was found, or throws on a network error.
    /// Searches the local store first, then the Chinese stores for songs with Chinese titles.
    private static func lookUp(artist: String, album: String, title: String) async throws -> Data? {
        let entity = album.isEmpty ? "song" : "album"
        let name = album.isEmpty ? title : album
        var countries = [Locale.current.region?.identifier ?? "US"]
        if (artist + name).unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
            countries += ["CN", "TW", "HK"]
        }
        var seen = Set<String>()
        for country in countries where seen.insert(country.uppercased()).inserted {
            var components = URLComponents(string: "https://itunes.apple.com/search")
            components?.queryItems = [
                URLQueryItem(name: "term", value: "\(artist) \(name)"),
                URLQueryItem(name: "entity", value: entity),
                URLQueryItem(name: "country", value: country),
                URLQueryItem(name: "limit", value: "10"),
            ]
            guard let url = components?.url else { continue }
            let searchData = try await ImageService.shared.fetchImageData(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { continue }
            // The search is fuzzy: only accept a result whose artist and album (or track) match.
            let nameField = album.isEmpty ? "trackName" : "collectionName"
            guard let match = results.first(where: { result in
                      matches(result["artistName"] as? String, artist) && matches(result[nameField] as? String, name)
                  }),
                  let small = match["artworkUrl100"] as? String,
                  let artworkURL = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            else { continue }
            let artwork = try await ImageService.shared.fetchImageData(from: artworkURL)
            if NSImage(data: artwork) != nil { return artwork }
        }
        return nil
    }

    /// Loose comparison that tolerates case, accents, width, and suffixes such as
    /// "(Deluxe Edition)" or " - Single" on either side.
    private static func matches(_ candidate: String?, _ expected: String) -> Bool {
        guard let candidate else { return false }
        let normalize = { (string: String) in
            string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let a = normalize(candidate), b = normalize(expected)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }
}
