// SPDX-License-Identifier: GPL-3.0-only
#if canImport(ImageIO)
import Foundation
import CoreGraphics
import ImageIO

/// Called on a worker task, never on the UI thread. One image is decoded at a
/// time. Originals and existing outputs are never overwritten.
enum PocketImageProcessor {
    static func process(_ url: URL, action: PocketImageAction, options: PocketImageOptions) throws -> PocketImageResult {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw PocketImageError.notImage
        }
        guard CGImageSourceGetCount(source) == 1 else { throw PocketImageError.multipleFrames }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PocketImageError.decode }
        guard Double(width) * Double(height) <= 80_000_000, max(width, height) <= 32_000 else { throw PocketImageError.tooLarge }
        let originalType = CGImageSourceGetType(source) as String? ?? ""
        let format: PocketImageFormat
        if action == .convert { format = options.format }
        else { format = PocketImageFormat.allCases.first { $0.typeIdentifier == originalType } ?? options.format }
        guard (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(format.typeIdentifier) else {
            throw PocketImageError.unsupportedEncoder
        }
        let maxSize = action == .resize ? min(max(width, height), max(1, options.longestEdge)) : max(width, height)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw PocketImageError.decode
        }
        if format == .jpeg { image = try flattened(image) }
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else {
            throw PocketImageError.unsupportedEncoder
        }
        // The thumbnail API applies EXIF orientation; mark the output upright.
        var outputProperties = properties
        outputProperties[kCGImagePropertyOrientation] = 1
        outputProperties[kCGImagePropertyPixelWidth] = image.width
        outputProperties[kCGImagePropertyPixelHeight] = image.height
        if var tiff = outputProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            outputProperties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            outputProperties[kCGImagePropertyExifDictionary] = exif
        }
        if format != .png {
            outputProperties[kCGImageDestinationLossyCompressionQuality] = options.quality.isFinite ? min(1, max(0.1, options.quality)) : 0.8
        }
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PocketImageError.encode }
        let inputBytes = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        // Compression must not leave a larger duplicate next to the source.
        if action == .compress, data.length >= inputBytes {
            return PocketImageResult(source: url, output: nil, inputBytes: inputBytes, outputBytes: inputBytes)
        }
        try Task.checkCancellation()
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".quotanotch-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try (data as Data).write(to: temporary, options: .withoutOverwriting)
        while true {
            try Task.checkCancellation()
            let output = PocketFiles.outputURL(for: url, suffix: action.rawValue, extension: format.fileExtension)
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
                return PocketImageResult(source: url, output: output, inputBytes: inputBytes, outputBytes: data.length)
            } catch {
                // Another writer may win between the name check and rename.
                guard (error as NSError).code == NSFileWriteFileExistsError else { throw error }
            }
        }
    }

    private static func flattened(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PocketImageError.decode }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw PocketImageError.decode }
        return result
    }
}
#endif
