// SPDX-License-Identifier: GPL-3.0-only
// Standalone rendering harness for the production pocket. No app services run.
import AppKit
import SwiftUI
import Metal

enum AgentText {
    static func t(_ zh: String, _ en: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
    }
}

private final class PocketPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@main
struct PocketPreviewRunner {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Metal: \(MTLCreateSystemDefaultDevice()?.name ?? "unavailable")")
        print("Reduce transparency: \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)")
        print("Increase contrast: \(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)")
        let language = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        let output = URL(fileURLWithPath: "build/Settings-previews/\(language)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try captureFilePocket(output: output)
    }
    @MainActor private static func captureFilePocket(output: URL) throws {
        for index in 0..<3 {
            let angle = Double(index - 1) * 40
            let point = CGPoint(x: CGFloat(174 + 106 * Darwin.cos(angle * .pi / 180)),
                                y: CGFloat(161 + 106 * Darwin.sin(angle * .pi / 180)))
            let hits = (0..<3).filter { other in
                PocketSectorShape(angle: Double(other - 1) * 40)
                    .path(in: CGRect(x: 36, y: 23, width: 276, height: 276)).contains(point)
            }
            verifyPresentation(hits == [index], "Pocket action hit regions overlap")
        }
        let suite = "FilePocketPreview-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let pocket = FilePocketStore(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for index in 0..<12 {
            let image = NSImage(size: NSSize(width: 96, height: 64))
            image.lockFocus()
            NSColor(calibratedHue: CGFloat(index) / 16, saturation: 0.3, brightness: 0.8, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 96, height: 64).fill()
            image.unlockFocus()
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            let url = directory.appendingPathComponent("Image-\(index + 1).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            urls.append(url)
        }
        pocket.add(urls)
        pocket.expanded = true
        let restored = FilePocketStore(defaults: defaults)
        verifyPresentation(restored.items.count == urls.count, "Pocket bookmarks did not restore")
        if ProcessInfo.processInfo.environment["FILE_POCKET_DESKTOP_CAPTURE"] == "1" {
            try capturePocketDesktop(pocket, output: output)
        }
    }

    /// Window-server captures, including the real backdrop, are necessary for
    /// visual effects. cacheDisplay alone flattens them into opaque placeholders.
    @MainActor private static func capturePocketDesktop(_ pocket: FilePocketStore, output: URL) throws {
        let size = NSSize(width: 600, height: 520)
        let origin = NSPoint(x: 80, y: 80)
        let backdrop = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        let panel = PocketPreviewPanel(contentRect: NSRect(origin: NSPoint(x: origin.x + 70, y: origin.y + 40), size: FilePocketController.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        defer {
            panel.orderOut(nil); panel.contentView = nil; panel.close()
            backdrop.orderOut(nil); backdrop.contentView = nil; backdrop.close()
        }
        for dark in [false, true] {
          for active in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            backdrop.appearance = appearance; panel.appearance = appearance
            backdrop.contentView = NSHostingView(rootView: ZStack {
                LinearGradient(colors: dark ? [Color(red: 0.08, green: 0.19, blue: 0.25), Color(red: 0.29, green: 0.38, blue: 0.39)] : [Color(red: 0.66, green: 0.82, blue: 0.85), Color(red: 0.86, green: 0.85, blue: 0.79)], startPoint: .bottomLeading, endPoint: .topTrailing)
                Ellipse().fill(.white.opacity(dark ? 0.08 : 0.24)).frame(width: 620, height: 280).rotationEffect(.degrees(-36)).offset(x: 100, y: -60)
            }.frame(width: size.width, height: size.height))
            panel.contentView = NSHostingView(rootView: FilePocketView(store: pocket))
            backdrop.orderFrontRegardless(); panel.orderFrontRegardless()
            if active { panel.makeKeyAndOrderFront(nil) } else { panel.resignKey() }
            print("Panel key: \(panel.isKeyWindow), active probe: \(active)")
            for expanded in [false, true] {
                pocket.expanded = expanded
                RunLoop.current.run(until: Date().addingTimeInterval(1.8))
                let screenHeight = NSScreen.screens[0].frame.height
                let region = "\(Int(origin.x)),\(Int(screenHeight - origin.y - size.height)),\(Int(size.width)),\(Int(size.height))"
                let destination = output.appendingPathComponent("File-pocket-desktop-\(active ? "active" : "inactive")-\(dark ? "dark" : "light")-\(expanded ? "open" : "closed").png")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-R", region, destination.path]
                try process.run(); process.waitUntilExit()
                verifyPresentation(process.terminationStatus == 0 && FileManager.default.fileExists(atPath: destination.path), "Window-server screenshot failed")
            }
        }
    }


    }

    private static func verifyPresentation(_ condition: Bool, _ message: @autoclosure () -> String) {
        precondition(condition, message())
    }
}
