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

        guard let empty = images["count-0"], let countOne = images["count-1"],
              let countTwo = images["count-2"], let countThree = images["count-3"],
              let countSix = images["count-6"],
              let lightNear = images["light-near"], let lightRim = images["light-rim"],
              let patternReference = images["transmission-background"],
              let patternThroughShell = images["transmission-patterned"],
              let smallEmpty = images["small-count-0"],
              let smallOne = images["small-count-1"],
              let smallTwo = images["small-count-2"],
              let smallThree = images["small-count-3"],
              let smallSix = images["small-count-6"],
              let historyThree = images["history-3"],
              let historyFour = images["history-4"],
              let historyFive = images["history-5"],
              let historySix = images["history-6"],
              let smallHistoryThree = images["small-history-3"],
              let smallHistoryFour = images["small-history-4"],
              let smallHistoryFive = images["small-history-5"],
              let smallHistorySix = images["small-history-6"],
              let historySixWithoutFourth = images["history-6-no-fourth"],
              let smallHistorySixWithoutFourth = images["small-history-6-no-fourth"] else {
            throw BubbleLabError.capture("snapshot plan omitted a required comparison state")
        }
        for (count, image) in [(1, countOne), (2, countTwo), (3, countThree), (6, countSix)] {
            guard difference(empty, image) > 0.004 else {
                throw BubbleLabError.capture("the \(count)-item state did not visibly show its built-in preview arrangement")
            }
        }
        guard difference(lightNear, lightRim) > 0.002 else {
            throw BubbleLabError.capture("pointer positions did not change the captured reflected environment")
        }
        guard spatialLightingChange(lightNear, lightRim) > 0.003 else {
            throw BubbleLabError.capture("pointer movement changed overall color but did not move reflected light across the shell")
        }
        guard patternTransmission(background: patternReference, shell: patternThroughShell) > 0.45 else {
            throw BubbleLabError.capture("the shell did not preserve enough of the patterned native backdrop through its center")
        }
        for (count, image) in [(1, smallOne), (2, smallTwo), (3, smallThree), (6, smallSix)] {
            guard localizedDifference(smallEmpty, image, center: CGPoint(x: 160, y: 160), insideRadius: 58) > 0.002,
                  localizedDifference(smallEmpty, image, center: CGPoint(x: 160, y: 160), outsideRadius: 67, maximumRadius: 112) < 0.001 else {
                throw BubbleLabError.capture("the \(count)-item previews are missing or escape the 64-point shell")
            }
        }
        guard difference(countThree, countSix) > 0.002,
              difference(historyThree, historyFour) > 0.002,
              difference(historyFour, historyFive) > 0.002,
              difference(historyFive, historySix) > 0.002,
              localizedDifference(smallThree, smallSix, center: CGPoint(x: 160, y: 160), insideRadius: 58) > 0.00015,
              localizedDifference(smallHistoryThree, smallHistoryFour, center: CGPoint(x: 160, y: 160), insideRadius: 58) > 0.00015,
              localizedDifference(smallHistoryFour, smallHistoryFive, center: CGPoint(x: 160, y: 160), insideRadius: 58) > 0.00015,
              localizedDifference(smallHistoryFive, smallHistorySix, center: CGPoint(x: 160, y: 160), insideRadius: 58) > 0.00015,
              lowerPeekingDifference(
                historySix,
                historySixWithoutFourth,
                center: CGPoint(x: 512, y: 512),
                bubbleDiameter: 226
              ) > 0.003,
              lowerPeekingDifference(
                smallHistorySix,
                smallHistorySixWithoutFourth,
                center: CGPoint(x: 160, y: 160),
                bubbleDiameter: 64
              ) > 0.0005 else {
            throw BubbleLabError.capture("the 3→4→5 history must reflow and show a blurred fourth preview peeking below the group")
        }

        let comparison = try render(BubbleCountComparisonScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28),
            arrival: .resting
        ), size: BubbleCountComparisonScene.size)
        try writePNG(comparison, to: outputDirectory.appendingPathComponent("count-comparison.png"))
        let historyComparison = try render(BubbleInsertionComparisonScene(
            time: 1.4,
            light: SIMD2<Float>(0.34, 0.28)
        ), size: BubbleInsertionComparisonScene.size)
        try writePNG(historyComparison, to: outputDirectory.appendingPathComponent("insertion-comparison.png"))

        try writeReport(CaptureReport(
            host: ProcessInfo.processInfo.operatingSystemVersionString,
            graphicsDevice: device.name,
            metalAvailable: true,
            shaderAvailable: true,
            renderer: "SwiftUI ImageRenderer with the app's compiled Metal library",
            snapshots: snapshots.map { "\($0.name).png" } + ["count-comparison.png", "insertion-comparison.png"],
            movies: [],
            result: "native count and lighting snapshots passed; movie encoding pending",
            limitation: nil
        ), to: reportURL)

        let lightSweepURL = outputDirectory.appendingPathComponent("bubble-light-sweep.mp4")
        try await writeMovie(to: lightSweepURL, kind: .lightSweep)
        let arrivalURL = outputDirectory.appendingPathComponent("bubble-arrival.mp4")
        try await writeMovie(to: arrivalURL, kind: .arrival)
        let insertionURL = outputDirectory.appendingPathComponent("bubble-file-insertion.mp4")
        try await writeMovie(to: insertionURL, kind: .insertion)

        try writeReport(CaptureReport(
            host: ProcessInfo.processInfo.operatingSystemVersionString,
            graphicsDevice: device.name,
            metalAvailable: true,
            shaderAvailable: true,
            renderer: "SwiftUI ImageRenderer with the app's compiled Metal library",
            snapshots: snapshots.map { "\($0.name).png" } + ["count-comparison.png", "insertion-comparison.png"],
            movies: [lightSweepURL.lastPathComponent, arrivalURL.lastPathComponent, insertionURL.lastPathComponent],
            result: "passed",
            limitation: nil
        ), to: reportURL)
    }

    private static let snapshotPlan: [(name: String, scene: BubbleScene)] = {
        let light = SIMD2<Float>(0.34, 0.28)
        func historyScene(_ count: Int, small: Bool = false, showsFourthPreview: Bool = true) -> BubbleScene {
            let moment: TimeInterval = switch count {
            case 3: 0
            case 4: BubbleInsertionTimeline.settledFourTime
            default: BubbleInsertionTimeline.settledFiveTime
            }
            let frame = count == 6
                ? BubbleInsertionFrame(count: 6, placements: BubbleItemLayout.placements(for: 6))
                : BubbleInsertionTimeline.frame(at: moment)
            return BubbleScene(
                time: 1.4,
                light: light,
                itemCount: frame.count,
                insertionFrame: frame,
                arrival: .resting,
                canvasSize: small ? CGSize(width: 160, height: 160) : canvasSize,
                bubbleDiameter: small ? 64 : 226,
                backdropStyle: small ? .pearl : .night,
                showsFourthPreview: showsFourthPreview
            )
        }
        var scenes = BubbleItemLayout.sampleCounts.map { count in
            ("count-\(count)", BubbleScene(time: 1.4, light: light, itemCount: count, arrival: .resting))
        }
        scenes += BubbleItemLayout.sampleCounts.map { count in
            ("small-count-\(count)", BubbleScene(
                time: 1.4,
                light: light,
                itemCount: count,
                arrival: .resting,
                canvasSize: CGSize(width: 160, height: 160),
                bubbleDiameter: 64,
                backdropStyle: .pearl
            ))
        }
        scenes += [
            ("history-3", historyScene(3)),
            ("history-4", historyScene(4)),
            ("history-5", historyScene(5)),
            ("history-6", historyScene(6)),
            ("history-6-no-fourth", historyScene(6, showsFourthPreview: false)),
            ("small-history-3", historyScene(3, small: true)),
            ("small-history-4", historyScene(4, small: true)),
            ("small-history-5", historyScene(5, small: true)),
            ("small-history-6", historyScene(6, small: true)),
            ("small-history-6-no-fourth", historyScene(6, small: true, showsFourthPreview: false)),
            ("light-near", BubbleScene(time: 1.4, light: SIMD2<Float>(0.18, 0.22), itemCount: 0, arrival: .resting)),
            ("light-center", BubbleScene(time: 1.4, light: SIMD2<Float>(0.50, 0.50), itemCount: 0, arrival: .resting)),
            ("light-rim", BubbleScene(time: 1.4, light: SIMD2<Float>(0.84, 0.78), itemCount: 0, arrival: .resting)),
            ("light-empty", BubbleScene(time: 1.4, light: light, itemCount: 0, arrival: .resting, backdropStyle: .pearl)),
            ("light-populated", BubbleScene(time: 1.4, light: light, itemCount: 2, arrival: .resting, backdropStyle: .pearl)),
            ("transmission-background", BubbleScene(
                time: 1.4,
                light: light,
                itemCount: 0,
                arrival: .resting,
                backdropStyle: .patterned,
                showsBubble: false
            )),
            ("transmission-patterned", BubbleScene(
                time: 1.4,
                light: light,
                itemCount: 0,
                arrival: .resting,
                backdropStyle: .patterned
            )),
            ("arrival-gather", BubbleScene(time: 2.6, light: SIMD2<Float>(0.35, 0.24), itemCount: 3, arrival: BubbleMotion.arrival(at: 0.34))),
            ("arrival-hold", BubbleScene(time: 2.9, light: SIMD2<Float>(0.35, 0.24), itemCount: 3, arrival: BubbleMotion.arrival(at: 0.45 + 0.45))),
            ("arrival-collapse", BubbleScene(time: 3.2, light: SIMD2<Float>(0.35, 0.24), itemCount: 3, arrival: BubbleMotion.arrival(at: 0.45 + 0.90 + 0.55)))
        ]
        return scenes.map { (name: $0.0, scene: $0.1) }
    }()

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

    /// Compares only the narrow lower sliver just beyond the sharp stack.
    /// This checks that the fourth layer contributes its actual blurred card
    /// face there, instead of passing on a global tint or a generic outline.
    private static func lowerPeekingDifference(
        _ image: CGImage,
        _ withoutFourth: CGImage,
        center: CGPoint,
        bubbleDiameter: CGFloat
    ) -> Double {
        let imageBitmap = NSBitmapImageRep(cgImage: image)
        let referenceBitmap = NSBitmapImageRep(cgImage: withoutFourth)
        let pixelsPerPoint = renderScale
        let xRadius = Int(bubbleDiameter * 0.22 * pixelsPerPoint)
        func bandDifference(direction: CGFloat) -> Double {
            let yStart = Int(center.y + direction * bubbleDiameter * 0.275 * pixelsPerPoint)
            let yEnd = Int(center.y + direction * bubbleDiameter * 0.335 * pixelsPerPoint)
            var total = 0.0
            var count = 0
            for y in stride(from: max(0, min(yStart, yEnd)), to: min(image.height, max(yStart, yEnd)), by: 2) {
                for x in stride(from: max(0, Int(center.x) - xRadius), to: min(image.width, Int(center.x) + xRadius), by: 2) {
                    guard let a = rgb(imageBitmap, x: x, y: y),
                          let b = rgb(referenceBitmap, x: x, y: y) else { continue }
                    total += zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) }
                    count += 1
                }
            }
            return count > 0 ? total / Double(count) : 0
        }
        return max(bandDifference(direction: -1), bandDifference(direction: 1))
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
        case insertion
    }

    private static func writeMovie(to url: URL, kind: MovieKind) async throws {
        try? FileManager.default.removeItem(at: url)
        let outputSize: CGSize
        switch kind {
        case .lightSweep, .arrival, .insertion:
            outputSize = canvasSize
        }
        let width = Int(outputSize.width * renderScale)
        let height = Int(outputSize.height * renderScale)
        let fps: Int32 = 30
        let duration: Double
        switch kind {
        case .arrival:
            duration = BubbleMotion.totalDuration + 0.10
        case .lightSweep:
            duration = 8.0
        case .insertion:
            duration = BubbleInsertionTimeline.duration
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
                pointer = SIMD2<Float>(0.5 + 0.42 * Float(cos(angle)), 0.5 + 0.36 * Float(sin(angle)))
                arrival = .resting
            case .insertion:
                pointer = SIMD2<Float>(0.34, 0.28)
                arrival = .resting
            }
            let image: CGImage
            if case .insertion = kind {
                let frame = BubbleInsertionTimeline.frame(at: time)
                image = try render(BubbleScene(
                    time: 1.4,
                    light: pointer,
                    itemCount: frame.count,
                    insertionFrame: frame,
                    arrival: .resting
                ), size: outputSize)
            } else if case .lightSweep = kind {
                // The only changing input is the environment-light direction.
                // Holding time and itemCount still makes curvature easy to judge.
                image = try render(BubbleScene(
                    time: 1.4,
                    light: pointer,
                    itemCount: 0,
                    arrival: .resting
                ), size: outputSize)
            } else {
                image = try render(BubbleScene(
                    time: 4.0 + time,
                    light: pointer,
                    itemCount: 3,
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
