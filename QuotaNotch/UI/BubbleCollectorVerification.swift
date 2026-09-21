// SPDX-License-Identifier: GPL-3.0-only
#if SETTINGS_PREVIEW
import AppKit
import Foundation

/// Exercises the collector's injected selection and private pasteboard paths in
/// the preview app. It never calls Accessibility APIs or touches another app.
@MainActor
enum BubbleCollectorVerification {
    static func run() throws {
        let store = BubbleShelfStore.shared
        let controller = BubbleCollectorController.shared
        let fixtureText = "collector fixture \(UUID().uuidString)"
        store.configurePreview(items: [
            BubbleShelfItem(kind: .text, title: "Existing fixture", text: "existing shelf item")
        ])
        store.isReceiving = true
        defer {
            controller.hidePreviewForTesting()
            controller.shutdown()
            store.resetPreviewConfiguration()
        }

        let anchor = CGPoint(x: 320, y: 320)
        controller.showSelectionForTesting(contents: [.text(fixtureText)], anchor: anchor)
        guard let panel = collectorPanel() else {
            throw VerificationError("Collector panel was not created for an injected selection")
        }
        guard panel.styleMask.contains(.nonactivatingPanel), panel.canBecomeKey == false else {
            throw VerificationError("Collector panel is not a nonactivating panel")
        }
        settle(0.05)
        try sendClick(to: panel)
        settle(0.12)
        guard store.items.contains(where: { $0.text == fixtureText }),
              store.lastImportResult?.succeeded == true else {
            throw VerificationError("Synthetic panel click did not retain the selected text")
        }

        // A replacement capture cancels the prior expiration task; the fresh
        // presentation must remain visible during that old task's deadline.
        controller.showPreviewForTesting(contents: [], anchor: anchor)
        controller.showPreviewForTesting(contents: [.stored(store.items[0])], anchor: anchor)
        settle(1.70)
        guard controller.presentation != nil else {
            throw VerificationError("A canceled collector expiration hid a newer presentation")
        }

        let dropBoard = NSPasteboard(name: .init("collector-fixture-drop-\(UUID().uuidString)"))
        let unsupportedBoard = NSPasteboard(name: .init("collector-fixture-unsupported-\(UUID().uuidString)"))
        defer {
            dropBoard.clearContents()
            unsupportedBoard.clearContents()
        }
        dropBoard.clearContents()
        dropBoard.declareTypes([.string], owner: nil)
        let dropText = "drop fixture \(UUID().uuidString)"
        guard dropBoard.setString(dropText, forType: .string),
              controller.receiveDrop(dropBoard, sourceProcessID: 42),
              store.items.contains(where: { $0.text == dropText }) else {
            throw VerificationError("Private pasteboard drop was not imported through the collector")
        }
        unsupportedBoard.clearContents()
        unsupportedBoard.declareTypes([.init("com.example.unsupported")], owner: nil)
        guard !controller.receiveDrop(unsupportedBoard, sourceProcessID: 42),
              !controller.receiveDrop(dropBoard, sourceProcessID: ProcessInfo.processInfo.processIdentifier) else {
            throw VerificationError("Collector accepted unsupported or self-originated content")
        }

        controller.pauseReceiving()
        guard controller.presentation == nil,
              controller.availability == .disabled,
              !store.isReceiving else {
            throw VerificationError("Pausing receive mode did not hide and stop the collector")
        }
    }

    private static func collectorPanel() -> NSPanel? {
        NSApp.windows.compactMap { $0 as? NSPanel }.first {
            $0.identifier == NSUserInterfaceItemIdentifier("bubble-collector-preview-panel")
        }
    }

    private static func sendClick(to window: NSWindow) throws {
        guard let contentView = window.contentView else {
            throw VerificationError("Collector panel has no content view")
        }
        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds
        let location = CGPoint(x: bounds.midX, y: bounds.midY)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location,
                                            modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil,
                                            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location,
                                          modifierFlags: [], timestamp: 0.01,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw VerificationError("Could not synthesize a collector click event")
        }
        window.sendEvent(down)
        window.sendEvent(up)
    }

    private static func settle(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
        }
    }

    private struct VerificationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
#endif
