import XCTest
@testable import QuotaNotchCore

final class FilePocketTests: XCTestCase {
    func testDoubleShiftRequiresTwoCompleteShortTaps() {
        var gesture = PocketShiftGesture()
        XCTAssertFalse(gesture.update(shift: true, otherModifier: false, at: 1))
        XCTAssertFalse(gesture.update(shift: false, otherModifier: false, at: 1.1))
        XCTAssertFalse(gesture.update(shift: true, otherModifier: false, at: 1.2))
        XCTAssertTrue(gesture.update(shift: false, otherModifier: false, at: 1.3))
        XCTAssertFalse(gesture.update(shift: false, otherModifier: false, at: 1.31))
    }
    func testHoldTypingAndModifierChordsDoNotTrigger() {
        var gesture = PocketShiftGesture()
        _ = gesture.update(shift: true, otherModifier: false, at: 1)
        _ = gesture.update(shift: false, otherModifier: false, at: 2)
        _ = gesture.update(shift: true, otherModifier: false, at: 2.1)
        XCTAssertFalse(gesture.update(shift: false, otherModifier: false, at: 2.2))
        gesture.reset() // Any keyDown invalidates the tap sequence.
        _ = gesture.update(shift: true, otherModifier: false, at: 2.3)
        XCTAssertFalse(gesture.update(shift: false, otherModifier: false, at: 2.4))
        _ = gesture.update(shift: true, otherModifier: true, at: 2.5)
        XCTAssertFalse(gesture.update(shift: false, otherModifier: false, at: 2.6))
    }
    func testSlowTapsDoNotTrigger() {
        var gesture = PocketShiftGesture()
        _ = gesture.update(shift: true, otherModifier: false, at: 1)
        _ = gesture.update(shift: false, otherModifier: false, at: 1.1)
        _ = gesture.update(shift: true, otherModifier: false, at: 2)
        XCTAssertFalse(gesture.update(shift: false, otherModifier: false, at: 2.1))
    }
    func testMergePreservesOrderAndResolvesSymlinkDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = directory.appendingPathComponent("a.png"), b = directory.appendingPathComponent("b.png"), link = directory.appendingPathComponent("alias.png")
        try Data([1]).write(to: a); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        XCTAssertEqual(PocketFiles.merged([a], [link, b, a, URL(string: "https://example.com/a.png")!]), [a, b])
    }
    func testOutputNamingNeverReusesSourceOrExistingName() {
        let url = URL(fileURLWithPath: "/images/photo.png")
        let taken: Set<String> = ["/images/photo-convert.jpg", "/images/photo-convert-1.jpg"]
        XCTAssertEqual(PocketFiles.outputURL(for: url, suffix: "convert", extension: "jpg", exists: taken.contains).path, "/images/photo-convert-2.jpg")
    }
}

#if canImport(ImageIO)
import ImageIO
import CoreGraphics

final class PocketImageProcessorTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture(_ directory: URL, orientation: Int = 1) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.5))
        context.fill(CGRect(x: 8, y: 4, width: 16, height: 8))
        let image = try XCTUnwrap(context.makeImage()), url = directory.appendingPathComponent("fixture.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return url
    }
    private func dimensions(_ url: URL) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }
    func testConversionPreservesOriginalAndDoesNotOverwriteExistingOutput() throws {
        let url = try fixture(directory()), original = try Data(contentsOf: url)
        let options = PocketImageOptions(format: .jpeg, quality: 0.8, longestEdge: 1920)
        let first = try PocketImageProcessor.process(url, action: .convert, options: options)
        let firstURL = try XCTUnwrap(first.output), firstData = try Data(contentsOf: firstURL)
        let second = try PocketImageProcessor.process(url, action: .convert, options: options)
        XCTAssertNotEqual(first.output, second.output)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData)
        XCTAssertEqual(try dimensions(firstURL).0, 32)
        XCTAssertTrue(firstURL.lastPathComponent.hasSuffix(".jpg"))
    }
    func testResizeKeepsAspectRatioAndDoesNotUpscale() throws {
        let url = try fixture(directory())
        let small = try PocketImageProcessor.process(url, action: .resize, options: .init(longestEdge: 8))
        let size = try dimensions(XCTUnwrap(small.output))
        XCTAssertEqual(size.0, 8); XCTAssertEqual(size.1, 4)
        let larger = try PocketImageProcessor.process(url, action: .resize, options: .init(longestEdge: 1280))
        let originalSize = try dimensions(XCTUnwrap(larger.output))
        XCTAssertEqual(originalSize.0, 32); XCTAssertEqual(originalSize.1, 16)
    }
    func testJPEGFlattensTransparencyToWhite() throws {
        let url = try fixture(directory())
        let result = try PocketImageProcessor.process(url, action: .convert, options: .init())
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(result.output) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let c = try XCTUnwrap(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 128,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        c.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 16))
        let bytes = try XCTUnwrap(c.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(bytes[0], 240); XCTAssertGreaterThan(bytes[1], 240); XCTAssertGreaterThan(bytes[2], 240)
    }
    func testRejectsNonImageWithoutWritingOutput() throws {
        let dir = try directory(), url = dir.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try PocketImageProcessor.process(url, action: .convert, options: .init()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["note.txt"])
    }
    func testRejectsAnimationInsteadOfSilentlyDroppingFrames() throws {
        let dir = try directory(), url = try fixture(dir)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let gif = dir.appendingPathComponent("animation.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(gif as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        CGImageDestinationAddImage(destination, image, nil); CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try PocketImageProcessor.process(gif, action: .convert, options: .init())) { error in
            guard case PocketImageError.multipleFrames = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}
#endif
