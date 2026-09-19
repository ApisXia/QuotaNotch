import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main struct TaskStatusDesignPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        func board(_ elapsed: Double) -> some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text("任务状态").frame(width: 86, alignment: .leading)
                    Text("widget · 20").frame(width: 65)
                    Text("minimal · 14").frame(width: 65)
                    Text("minimal · 10").frame(width: 65)
                    Text("列表 · 6").frame(width: 65)
                    Text("细节放大").frame(width: 58)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(AgentRunState.allCases, id: \.self) { state in
                    HStack(spacing: 8) {
                        Text(AgentText.state(state)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).frame(width: 86, alignment: .leading)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(1.25).frame(width: 65)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(0.875).frame(width: 65)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(0.625).frame(width: 65)
                        AgentTaskStateMark(state: state, previewElapsed: elapsed).frame(width: 65)
                        AgentPaperGlyph(state: state, previewElapsed: elapsed).scaleEffect(2.4).frame(width: 58)
                    }.frame(height: 32)
                }
            }.padding(22).frame(width: 510, height: 360).background(.black).preferredColorScheme(.dark)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 360), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let output = URL(fileURLWithPath: "build/task-status-output")
        let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("Task-status-refined.gif") as CFURL, UTType.gif.identifier as CFString, 270, nil)!
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<270 {
            let renderer = ImageRenderer(content: board(Double(frame) / 15).environment(\.colorScheme, .dark))
            renderer.scale = 1
            guard let cgImage = renderer.cgImage else { fatalError("Could not render task frame") }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            CGImageDestinationAddImage(destination, bitmap.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
            if [0, 3, 6, 9, 18, 36].contains(frame) {
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Task-status-refined-\(frame).png"))
            }
        }
        precondition(CGImageDestinationFinalize(destination))
        print("Rendered original and refined production glyphs, 270 native frames over a seamless 18-second motion cycle.")
    }
}
