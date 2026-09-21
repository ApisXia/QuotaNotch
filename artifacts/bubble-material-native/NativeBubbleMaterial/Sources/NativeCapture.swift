import AVFoundation
import AppKit
import CoreVideo
import ImageIO
import Metal
import SwiftUI
import UniformTypeIdentifiers

private struct CaptureReport: Encodable {
    let host: String
    let graphicsDevice: String?
    let metalAvailable: Bool
    let shaderAvailable: Bool
    let renderer: String
    let snapshots: [String]
    let movies: [String]
    let result: String
    let limitation: String?
}

@MainActor
enum NativeCapture {
    private static let renderScale: CGFloat = 2
    private static let canvasSize = CGSize(width: 512, height: 512)

    static func run(outputDirectory: URL) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try BubbleChecks.run()

        let device = MTLCreateSystemDefaultDevice()
        let library = try? device?.makeDefaultLibrary(bundle: .main)
        let shaderAvailable = library?.functionNames.contains("pearlFilm") == true
        let reportURL = outputDirectory.appendingPathComponent("render-report.json")

        guard let device else {
            try writeReport(CaptureReport(
                host: ProcessInfo.processInfo.operatingSystemVersionString,
                graphicsDevice: nil,
                metalAvailable: false,
                shaderAvailable: false,
                renderer: "SwiftUI ImageRenderer",
                snapshots: [],
                movies: [],
                result: "unavailable",
                limitation: "No Metal device is exposed by this macOS runner."
            ), to: reportURL)
            throw BubbleLabError.capability("Metal is unavailable on this runner; no native shader render is claimed.")
        }

        guard shaderAvailable else {
            try writeReport(CaptureReport(
                host: ProcessInfo.processInfo.operatingSystemVersionString,
                graphicsDevice: device.name,
                metalAvailable: true,
                shaderAvailable: false,
                renderer: "SwiftUI ImageRenderer",
                snapshots: [],
                movies: [],
                result: "unavailable",
                limitation: "The app bundle does not expose the compiled pearlFilm shader."
            ), to: reportURL)
            throw BubbleLabError.capability("Metal is available, but the compiled pearlFilm shader could not be loaded.")
        }

        let snapshots = snapshotPlan
        var images: [String: CGImage] = [:]
        for snapshot in snapshots {
            let image = try render(snapshot.scene)
            try validate(image: image, named: snapshot.name, expectedSize: snapshot.scene.canvasSize)
            try writePNG(image, to: outputDirectory.appendingPathComponent("\(snapshot.name).png"))
            images[snapshot.name] = image
        }

        guard let empty = images["empty"], let populated = images["populated"],
              let lightNear = images["light-near"], let lightFar = images["light-far"],
              let lightEmpty = images["light-empty"] else {
            throw BubbleLabError.capture("snapshot plan omitted a required comparison state")
        }
        guard difference(empty, populated) > 0.004 else {
            throw BubbleLabError.capture("empty and populated captures did not differ enough to show the three flakes")
        }
        guard difference(lightNear, lightFar) > 0.002 else {
            throw BubbleLabError.capture("pointer positions did not change the captured reflected environment")
        }
        guard centerDifference(empty, lightEmpty) > 0.20 else {
            throw BubbleLabError.capture("the shell center does not show enough of the light and dark environments through its translucent body")
        }

        try writeReport(CaptureReport(
            host: ProcessInfo.processInfo.operatingSystemVersionString,
            graphicsDevice: device.name,
            metalAvailable: true,
            shaderAvailable: true,
            renderer: "SwiftUI ImageRenderer with the app's compiled Metal library",
            snapshots: snapshots.map { "\($0.name).png" },
            movies: [],
            result: "native snapshots passed; movie encoding pending",
            limitation: nil
        ), to: reportURL)

        let lightSweepURL = outputDirectory.appendingPathComponent("bubble-light-sweep.mp4")
        try await writeMovie(to: lightSweepURL, kind: .lightSweep)
        let arrivalURL = outputDirectory.appendingPathComponent("bubble-arrival.mp4")
        try await writeMovie(to: arrivalURL, kind: .arrival)

        try writeReport(CaptureReport(
            host: ProcessInfo.processInfo.operatingSystemVersionString,
            graphicsDevice: device.name,
            metalAvailable: true,
            shaderAvailable: true,
            renderer: "SwiftUI ImageRenderer with the app's compiled Metal library",
            snapshots: snapshots.map { "\($0.name).png" },
            movies: [lightSweepURL.lastPathComponent, arrivalURL.lastPathComponent],
            result: "passed",
            limitation: nil
        ), to: reportURL)
    }

    private static let snapshotPlan: [(name: String, scene: BubbleScene)] = [
        ("empty", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: false, arrival: .resting)),
        ("populated", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: true, arrival: .resting)),
        ("light-near", BubbleScene(time: 2.1, light: SIMD2<Float>(0.16, 0.25), populated: true, arrival: .resting)),
        ("light-far", BubbleScene(time: 2.1, light: SIMD2<Float>(0.84, 0.69), populated: true, arrival: .resting)),
        ("light-empty", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: false, arrival: .resting, backdropStyle: .pearl)),
        ("light-populated", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: true, arrival: .resting, backdropStyle: .pearl)),
        ("small-widget-light", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: false,
            arrival: .resting,
            canvasSize: CGSize(width: 160, height: 160),
            bubbleDiameter: 64,
            backdropStyle: .pearl
        )),
        ("arrival-gather", BubbleScene(time: 2.6, light: SIMD2<Float>(0.35, 0.24), populated: true, arrival: BubbleMotion.arrival(at: 0.34))),
        ("arrival-hold", BubbleScene(time: 2.9, light: SIMD2<Float>(0.35, 0.24), populated: true, arrival: BubbleMotion.arrival(at: 0.45 + 0.45))),
        ("arrival-collapse", BubbleScene(time: 3.2, light: SIMD2<Float>(0.35, 0.24), populated: true, arrival: BubbleMotion.arrival(at: 0.45 + 0.90 + 0.55)))
    ]

    private static func render(_ scene: BubbleScene) throws -> CGImage {
        let renderer = ImageRenderer(content: scene)
        renderer.proposedSize = ProposedViewSize(width: scene.canvasSize.width, height: scene.canvasSize.height)
        renderer.scale = renderScale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else {
            throw BubbleLabError.capture("SwiftUI ImageRenderer returned no image")
        }
        return image
    }

    private static func validate(image: CGImage, named name: String, expectedSize: CGSize) throws {
        let expectedWidth = Int(expectedSize.width * renderScale)
        let expectedHeight = Int(expectedSize.height * renderScale)
        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw BubbleLabError.capture("\(name) frame has unexpected dimensions \(image.width)×\(image.height)")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let center = rgb(bitmap, x: expectedWidth / 2, y: expectedHeight / 2),
              let background = rgb(bitmap, x: expectedWidth / 8, y: expectedHeight / 8) else {
            throw BubbleLabError.capture("\(name) frame could not be sampled")
        }
        let delta = zip(center, background).reduce(0.0) { $0 + abs($1.0 - $1.1) }
        let minimumContrast = name.contains("light") ? 0.025 : 0.12
        guard delta > minimumContrast else {
            throw BubbleLabError.capture("\(name) frame is present but the center shell has no visible material contrast")
        }
    }

    private static func difference(_ first: CGImage, _ second: CGImage) -> Double {
        let firstBitmap = NSBitmapImageRep(cgImage: first)
        let secondBitmap = NSBitmapImageRep(cgImage: second)
        var total = 0.0
        var count = 0
        for y in stride(from: 400, through: 624, by: 28) {
            for x in stride(from: 400, through: 624, by: 28) {
                guard let a = rgb(firstBitmap, x: x, y: y), let b = rgb(secondBitmap, x: x, y: y) else { continue }
                total += zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) }
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    private static func centerDifference(_ first: CGImage, _ second: CGImage) -> Double {
        let centerX = first.width / 2
        let centerY = first.height / 2
        let firstBitmap = NSBitmapImageRep(cgImage: first)
        let secondBitmap = NSBitmapImageRep(cgImage: second)
        guard let a = rgb(firstBitmap, x: centerX, y: centerY),
              let b = rgb(secondBitmap, x: centerX, y: centerY) else { return 0 }
        return zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) }
    }

    private static func rgb(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> [Double]? {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return nil }
        return [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw BubbleLabError.capture("could not create PNG at \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BubbleLabError.capture("could not finish PNG at \(url.path)")
        }
    }

    private static func writeReport(_ report: CaptureReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private enum MovieKind {
        case lightSweep
        case arrival
    }

    private static func writeMovie(to url: URL, kind: MovieKind) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(canvasSize.width * renderScale)
        let height = Int(canvasSize.height * renderScale)
        let fps: Int32 = 30
        let duration: Double
        switch kind {
        case .arrival:
            duration = BubbleMotion.totalDuration + 0.10
        case .lightSweep:
            duration = 3.0
        }
        let frameCount = Int(duration * Double(fps))
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else {
            throw BubbleLabError.capture("AVFoundation cannot add an H.264 movie track")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw BubbleLabError.capture("AVFoundation could not start the movie writer: \(writer.error?.localizedDescription ?? "unknown error")")
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            let readinessWaitBegan = Date()
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else {
                    throw BubbleLabError.capture("AVFoundation stopped while waiting for frame \(frameIndex): \(writer.error?.localizedDescription ?? writer.status.rawValue.description)")
                }
                guard Date().timeIntervalSince(readinessWaitBegan) < 10 else {
                    throw BubbleLabError.capture("AVFoundation timed out while waiting for frame \(frameIndex)")
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let time = Double(frameIndex) / Double(fps)
            let pointer: SIMD2<Float>
            let arrival: ArrivalFrame
            switch kind {
            case .arrival:
                pointer = SIMD2<Float>(0.34, 0.30)
                arrival = BubbleMotion.arrival(at: time)
            case .lightSweep:
                let angle = time / duration * 2 * .pi - .pi / 2
                pointer = SIMD2<Float>(
                    0.5 + 0.32 * Float(cos(angle)),
                    0.5 + 0.27 * Float(sin(angle))
                )
                arrival = .resting
            }
            let scene = BubbleScene(
                time: 4.0 + time,
                light: pointer,
                populated: true,
                arrival: arrival
            )
            let image = try render(scene)
            guard let buffer = makePixelBuffer(from: image, width: width, height: height, pool: adaptor.pixelBufferPool) else {
                throw BubbleLabError.capture("AVFoundation could not allocate a frame buffer")
            }
            let presentationTime = CMTime(value: Int64(frameIndex), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw BubbleLabError.capture("AVFoundation rejected movie frame \(frameIndex): \(writer.error?.localizedDescription ?? "unknown error")")
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw BubbleLabError.capture("AVFoundation could not finish the movie: \(writer.error?.localizedDescription ?? "unknown error")")
        }
    }

    private static func makePixelBuffer(from image: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var optionalBuffer: CVPixelBuffer?
        let status: CVReturn
        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer)
        } else {
            status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32ARGB,
                [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                &optionalBuffer
            )
        }
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
