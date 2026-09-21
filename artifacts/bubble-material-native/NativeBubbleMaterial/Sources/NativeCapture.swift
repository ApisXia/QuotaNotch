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
        guard DemoArtwork.isAvailable else {
            throw BubbleLabError.capture("the built-in still-life preview image is missing from the app bundle")
        }

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
            let image = try render(snapshot.scene, size: snapshot.scene.canvasSize)
            try validate(
                image: image,
                named: snapshot.name,
                backdropStyle: snapshot.scene.backdropStyle,
                showsBubble: snapshot.scene.showsBubble,
                expectedSize: snapshot.scene.canvasSize
            )
            try writePNG(image, to: outputDirectory.appendingPathComponent("\(snapshot.name).png"))
            images[snapshot.name] = image
        }

        guard let empty = images["empty"], let populated = images["populated"],
              let lightNear = images["light-near"], let lightFar = images["light-far"],
              let patternReference = images["transmission-background"],
              let patternThroughShell = images["transmission-patterned"],
              let smallEmpty = images["small-widget-light"],
              let smallPopulated = images["small-widget-populated"],
              let smallInset = images["small-inset-pair"],
              let smallFloating = images["small-floating-pair"],
              let smallSoft = images["small-soft-stack"],
              let inset = images["variant-inset-pair"],
              let floating = images["variant-floating-pair"],
              let soft = images["variant-soft-stack"] else {
            throw BubbleLabError.capture("snapshot plan omitted a required comparison state")
        }
        guard difference(empty, populated) > 0.004 else {
            throw BubbleLabError.capture("empty and populated captures did not differ enough to show the built-in previews")
        }
        guard difference(lightNear, lightFar) > 0.002 else {
            throw BubbleLabError.capture("pointer positions did not change the captured reflected environment")
        }
        guard spatialLightingChange(lightNear, lightFar) > 0.003 else {
            throw BubbleLabError.capture("pointer movement changed overall color but did not move reflected light across the shell")
        }
        guard patternTransmission(background: patternReference, shell: patternThroughShell) > 0.45 else {
            throw BubbleLabError.capture("the shell did not preserve enough of the patterned native backdrop through its center")
        }
        guard localizedDifference(smallEmpty, smallPopulated, center: CGPoint(x: 160, y: 160), insideRadius: 56) > 0.002,
              localizedDifference(smallEmpty, smallPopulated, center: CGPoint(x: 160, y: 160), outsideRadius: 76, maximumRadius: 112) < 0.001 else {
            throw BubbleLabError.capture("the populated previews do not stay visible inside the 64-point shell")
        }
        for (name, image) in [("A·轻叠", smallInset), ("B·浮游", smallFloating), ("C·柔藏", smallSoft)] {
            guard localizedDifference(smallEmpty, image, center: CGPoint(x: 160, y: 160), insideRadius: 56) > 0.002,
                  localizedDifference(smallEmpty, image, center: CGPoint(x: 160, y: 160), outsideRadius: 76, maximumRadius: 112) < 0.001 else {
                throw BubbleLabError.capture("\(name) content is missing or escapes the 64-point shell")
            }
        }
        guard difference(inset, floating) > 0.002,
              difference(inset, soft) > 0.002,
              difference(floating, soft) > 0.002 else {
            throw BubbleLabError.capture("the three Chinese-labeled compositions rendered too similarly")
        }

        let comparison = try render(BubbleVariantComparisonScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            arrival: .resting
        ), size: BubbleVariantComparisonScene.size)
        try writePNG(comparison, to: outputDirectory.appendingPathComponent("variants-comparison.png"))

        try writeReport(CaptureReport(
            host: ProcessInfo.processInfo.operatingSystemVersionString,
            graphicsDevice: device.name,
            metalAvailable: true,
            shaderAvailable: true,
            renderer: "SwiftUI ImageRenderer with the app's compiled Metal library",
            snapshots: snapshots.map { "\($0.name).png" } + ["variants-comparison.png"],
            movies: [],
            result: "native snapshots passed; movie encoding pending",
            limitation: nil
        ), to: reportURL)

        let lightSweepURL = outputDirectory.appendingPathComponent("bubble-light-sweep.mp4")
        try await writeMovie(to: lightSweepURL, kind: .lightSweep)
        let arrivalURL = outputDirectory.appendingPathComponent("bubble-arrival.mp4")
        try await writeMovie(to: arrivalURL, kind: .arrival)
        let variantsURL = outputDirectory.appendingPathComponent("bubble-variants-comparison.mp4")
        try await writeMovie(to: variantsURL, kind: .variants)

        try writeReport(CaptureReport(
            host: ProcessInfo.processInfo.operatingSystemVersionString,
            graphicsDevice: device.name,
            metalAvailable: true,
            shaderAvailable: true,
            renderer: "SwiftUI ImageRenderer with the app's compiled Metal library",
            snapshots: snapshots.map { "\($0.name).png" } + ["variants-comparison.png"],
            movies: [lightSweepURL.lastPathComponent, arrivalURL.lastPathComponent, variantsURL.lastPathComponent],
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
        ("transmission-background", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: false,
            arrival: .resting,
            backdropStyle: .patterned,
            showsBubble: false
        )),
        ("transmission-patterned", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: false,
            arrival: .resting,
            backdropStyle: .patterned
        )),
        ("small-widget-light", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: false,
            arrival: .resting,
            canvasSize: CGSize(width: 160, height: 160),
            bubbleDiameter: 64,
            backdropStyle: .pearl
        )),
        ("small-widget-populated", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: true,
            arrival: .resting,
            canvasSize: CGSize(width: 160, height: 160),
            bubbleDiameter: 64,
            backdropStyle: .pearl
        )),
        ("variant-inset-pair", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: true, arrival: .resting, composition: .insetPair)),
        ("variant-floating-pair", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: true, arrival: .resting, composition: .floatingPair)),
        ("variant-soft-stack", BubbleScene(time: 1.4, light: SIMD2<Float>(0.34, 0.28), populated: true, arrival: .resting, composition: .softStack)),
        ("small-inset-pair", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: true,
            arrival: .resting,
            canvasSize: CGSize(width: 160, height: 160),
            bubbleDiameter: 64,
            backdropStyle: .pearl,
            composition: .insetPair
        )),
        ("small-floating-pair", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: true,
            arrival: .resting,
            canvasSize: CGSize(width: 160, height: 160),
            bubbleDiameter: 64,
            backdropStyle: .pearl,
            composition: .floatingPair
        )),
        ("small-soft-stack", BubbleScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            populated: true,
            arrival: .resting,
            canvasSize: CGSize(width: 160, height: 160),
            bubbleDiameter: 64,
            backdropStyle: .pearl,
            composition: .softStack
        )),
        ("arrival-gather", BubbleScene(time: 2.6, light: SIMD2<Float>(0.35, 0.24), populated: true, arrival: BubbleMotion.arrival(at: 0.34))),
        ("arrival-hold", BubbleScene(time: 2.9, light: SIMD2<Float>(0.35, 0.24), populated: true, arrival: BubbleMotion.arrival(at: 0.45 + 0.45))),
        ("arrival-collapse", BubbleScene(time: 3.2, light: SIMD2<Float>(0.35, 0.24), populated: true, arrival: BubbleMotion.arrival(at: 0.45 + 0.90 + 0.55)))
    ]

    private static func render<Content: View>(_ content: Content, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = renderScale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else {
            throw BubbleLabError.capture("SwiftUI ImageRenderer returned no image")
        }
        return image
    }

    private static func validate(
        image: CGImage,
        named name: String,
        backdropStyle: BubbleBackdropStyle,
        showsBubble: Bool,
        expectedSize: CGSize
    ) throws {
        let expectedWidth = Int(expectedSize.width * renderScale)
        let expectedHeight = Int(expectedSize.height * renderScale)
        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw BubbleLabError.capture("\(name) frame has unexpected dimensions \(image.width)×\(image.height)")
        }
        guard showsBubble else { return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let center = rgb(bitmap, x: expectedWidth / 2, y: expectedHeight / 2),
              let background = rgb(bitmap, x: expectedWidth / 8, y: expectedHeight / 8) else {
            throw BubbleLabError.capture("\(name) frame could not be sampled")
        }
        let delta = zip(center, background).reduce(0.0) { $0 + abs($1.0 - $1.1) }
        let minimumContrast = backdropStyle == .night ? 0.12 : 0.025
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

    private static func localizedDifference(
        _ first: CGImage,
        _ second: CGImage,
        center: CGPoint,
        insideRadius: CGFloat? = nil,
        outsideRadius: CGFloat? = nil,
        maximumRadius: CGFloat? = nil
    ) -> Double {
        let firstBitmap = NSBitmapImageRep(cgImage: first)
        let secondBitmap = NSBitmapImageRep(cgImage: second)
        var total = 0.0
        var count = 0
        for y in stride(from: 8, to: first.height - 8, by: 4) {
            for x in stride(from: 8, to: first.width - 8, by: 4) {
                let distance = hypot(CGFloat(x) - center.x, CGFloat(y) - center.y)
                if let insideRadius, distance > insideRadius { continue }
                if let outsideRadius, distance < outsideRadius { continue }
                if let maximumRadius, distance > maximumRadius { continue }
                guard let a = rgb(firstBitmap, x: x, y: y), let b = rgb(secondBitmap, x: x, y: y) else { continue }
                total += zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) }
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    private static func spatialLightingChange(_ first: CGImage, _ second: CGImage) -> Double {
        let firstBitmap = NSBitmapImageRep(cgImage: first)
        let secondBitmap = NSBitmapImageRep(cgImage: second)
        var positive = 0.0
        var negative = 0.0
        var count = 0
        let centerX = first.width / 2
        let centerY = first.height / 2
        for y in stride(from: centerY - 176, through: centerY + 176, by: 8) {
            for x in stride(from: centerX - 176, through: centerX + 176, by: 8) {
                let dx = x - centerX
                let dy = y - centerY
                guard dx * dx + dy * dy < 176 * 176,
                      let a = rgb(firstBitmap, x: x, y: y),
                      let b = rgb(secondBitmap, x: x, y: y) else { continue }
                let lumaA = a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722
                let lumaB = b[0] * 0.2126 + b[1] * 0.7152 + b[2] * 0.0722
                let delta = lumaA - lumaB
                positive += max(delta, 0)
                negative += max(-delta, 0)
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return min(positive, negative) / Double(count)
    }

    private static func patternTransmission(background: CGImage, shell: CGImage) -> Double {
        let backgroundBitmap = NSBitmapImageRep(cgImage: background)
        let shellBitmap = NSBitmapImageRep(cgImage: shell)
        let centerX = background.width / 2
        let centerY = background.height / 2
        let offsets = [(-48, -48), (48, -48), (-48, 48), (48, 48)]
        let backdropSamples = offsets.compactMap { rgb(backgroundBitmap, x: centerX + $0.0, y: centerY + $0.1) }
        let shellSamples = offsets.compactMap { rgb(shellBitmap, x: centerX + $0.0, y: centerY + $0.1) }
        guard backdropSamples.count == offsets.count, shellSamples.count == offsets.count else { return 0 }

        var signal = 0.0
        var covariance = 0.0
        for channel in 0..<3 {
            let backdropMean = backdropSamples.map { $0[channel] }.reduce(0, +) / Double(offsets.count)
            let shellMean = shellSamples.map { $0[channel] }.reduce(0, +) / Double(offsets.count)
            for sample in 0..<offsets.count {
                let sourceDelta = backdropSamples[sample][channel] - backdropMean
                let renderedDelta = shellSamples[sample][channel] - shellMean
                signal += sourceDelta * sourceDelta
                covariance += sourceDelta * renderedDelta
            }
        }
        return signal > 0 ? covariance / signal : 0
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
        case variants
    }

    private static func writeMovie(to url: URL, kind: MovieKind) async throws {
        try? FileManager.default.removeItem(at: url)
        let outputSize: CGSize
        switch kind {
        case .lightSweep, .arrival:
            outputSize = canvasSize
        case .variants:
            outputSize = BubbleVariantComparisonScene.size
        }
        let width = Int(outputSize.width * renderScale)
        let height = Int(outputSize.height * renderScale)
        let fps: Int32 = 30
        let duration: Double
        switch kind {
        case .arrival:
            duration = BubbleMotion.totalDuration + 0.10
        case .lightSweep, .variants:
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
            case .lightSweep, .variants:
                let angle = time / duration * 2 * .pi - .pi / 2
                pointer = SIMD2<Float>(
                    0.5 + 0.32 * Float(cos(angle)),
                    0.5 + 0.27 * Float(sin(angle))
                )
                arrival = .resting
            }
            let image: CGImage
            if case .variants = kind {
                image = try render(BubbleVariantComparisonScene(time: 4.0 + time, light: pointer, arrival: arrival), size: outputSize)
            } else {
                image = try render(BubbleScene(
                    time: 4.0 + time,
                    light: pointer,
                    populated: true,
                    arrival: arrival
                ), size: outputSize)
            }
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
