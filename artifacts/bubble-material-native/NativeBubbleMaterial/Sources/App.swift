import AppKit
import Darwin
import SwiftUI

@main
struct BubbleMaterialLabApp: App {
    @NSApplicationDelegateAdaptor(BubbleLabDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            InteractiveBubbleLab()
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class BubbleLabDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        guard let modeIndex = arguments.firstIndex(where: { $0 == "--self-test" || $0 == "--capture" }) else {
            return
        }

        Task { @MainActor in
            do {
                if arguments[modeIndex] == "--self-test" {
                    try BubbleChecks.run()
                    print("Bubble motion checks passed.")
                    exit(EXIT_SUCCESS)
                }

                guard modeIndex + 1 < arguments.count else {
                    throw BubbleLabError.argument("--capture needs an output directory")
                }
                try await NativeCapture.run(outputDirectory: URL(fileURLWithPath: arguments[modeIndex + 1]))
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Bubble material preview failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
    }
}

struct InteractiveBubbleLab: View {
    @State private var itemCount = 2
    @State private var pointer = SIMD2<Float>(0.34, 0.28)
    @State private var arrivalStartedAt: Date?

    private let startTime = Date()

    var body: some View {
        VStack(spacing: 18) {
            Text("内置示例预览 · 数量仅用于演示")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let time = context.date.timeIntervalSince(startTime)
                let elapsed = arrivalStartedAt.map { context.date.timeIntervalSince($0) }
                let arrival = elapsed.map { BubbleMotion.arrival(at: $0) } ?? .resting

                BubbleScene(
                    time: time,
                    light: pointer,
                    itemCount: itemCount,
                    arrival: arrival
                )
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            pointer = SIMD2<Float>(
                                Float(min(1, max(0, location.x / 512))),
                                Float(min(1, max(0, location.y / 512)))
                            )
                        case .ended:
                            pointer = SIMD2<Float>(0.34, 0.28)
                        }
                    }
            }
            .frame(width: 512, height: 512)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 14) {
                DoubleBubbleMark()
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Layered bubble notch symbol")
                Button("播放收拢") {
                    itemCount = max(itemCount, 1)
                    arrivalStartedAt = .now
                }
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 13, weight: .medium))

            Picker("示例项数", selection: Binding(
                get: { itemCount },
                set: { value in
                    itemCount = value
                    arrivalStartedAt = nil
                }
            )) {
                ForEach(BubbleItemLayout.sampleCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 512)
        }
        .padding(24)
        .background(Color(red: 0.025, green: 0.030, blue: 0.050))
        .preferredColorScheme(.dark)
    }
}

enum BubbleLabError: Error, CustomStringConvertible {
    case argument(String)
    case capability(String)
    case capture(String)

    var description: String {
        switch self {
        case .argument(let message), .capability(let message), .capture(let message): message
        }
    }
}
