// SPDX-License-Identifier: GPL-3.0-only
#if SETTINGS_PREVIEW
import AppKit
import Foundation

/// Exercises the holder lifecycle and storage paths with private fixtures. It
/// never asks for Accessibility/Finder permission and never reads a third
/// party application's selection.
@MainActor
enum BubbleCollectorVerification {
    static func run() throws {
        try verifyInjectedStorePersistence()
        try verifySharedHolderDropLifecycle()
    }

    private static func verifyInjectedStorePersistence() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("BubbleHolderVerification-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "QuotaNotch.BubbleHolder.Verification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw VerificationError("Could not create an isolated verification defaults suite")
        }
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let sourceFile = root.appendingPathComponent("source.txt", isDirectory: false)
        let sourceFolder = root.appendingPathComponent("source-folder", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceFolder, withIntermediateDirectories: false)
        try Data("original source".utf8).write(to: sourceFile)

        let first = BubbleShelfStore(storageDirectory: root, defaults: defaults)
        try check(!first.isReceiving, "Fresh injected holder must start hidden")
        try check(!first.isPinnedToNotch, "Pinned preference must default to false")
        try check(first.holderLocation == nil, "Fresh injected holder must have no saved location")

        try check(first.addFile(sourceFile).succeeded, "Real file fixture was not stored")
        try check(first.addFile(sourceFolder).succeeded, "Real folder fixture was not stored")
        try check(first.addText("persisted holder text").succeeded, "Text fixture was not stored")
        first.isPinnedToNotch = true
        first.holderLocation = CGPoint(x: 412, y: 236)
        first.isReceiving = true

        let restored = BubbleShelfStore(storageDirectory: root, defaults: defaults)
        try check(restored.isReceiving, "Persisted holder visibility was not restored")
        try check(restored.isPinnedToNotch, "Pinned preference was not restored")
        try check(restored.holderLocation == CGPoint(x: 412, y: 236),
                  "Holder location was not restored")
        try check(restored.items.contains(where: { sameFile($0.fileURL, sourceFile) }),
                  "Restored store lost the original file reference")
        try check(restored.items.contains(where: { $0.kind == .folder && sameFile($0.fileURL, sourceFolder) }),
                  "Restored store lost the original folder reference")
        try check(restored.items.contains(where: { $0.text == "persisted holder text" }),
                  "Restored store lost persisted text")

        restored.isReceiving = false
        let pausedRestore = BubbleShelfStore(storageDirectory: root, defaults: defaults)
        try check(!pausedRestore.isReceiving, "Pause state was not persisted")
        try check(pausedRestore.items.count == restored.items.count,
                  "Pausing changed stored shelf contents")
        try check(fileManager.fileExists(atPath: sourceFile.path),
                  "Pausing removed the original file")

        let manualBoard = NSPasteboard(name: .init("bubble-holder-verification-\(UUID().uuidString)"))
        manualBoard.clearContents()
        manualBoard.declareTypes([.string], owner: nil)
        try check(manualBoard.setString("manual paused drop", forType: .string),
                  "Could not prepare isolated drop pasteboard")
        let pausedDrop = pausedRestore.importPasteboardManually(manualBoard)
        try check(pausedDrop.succeeded && pausedRestore.items.contains(where: { $0.text == "manual paused drop" }),
                  "Manual holder drop did not work while receive mode was paused")
        manualBoard.clearContents()
        pausedRestore.clear()
        try check(fileManager.fileExists(atPath: sourceFile.path)
                    && fileManager.fileExists(atPath: sourceFolder.path),
                  "Clearing the shelf removed an original file or folder")
    }

    private static func verifySharedHolderDropLifecycle() throws {
        let store = BubbleShelfStore.shared
        let controller = BubbleCollectorController.shared
        store.resetPreviewConfiguration()
        controller.shutdown()
        defer {
            controller.shutdown()
            store.resetPreviewConfiguration()
        }

        try check(!store.isReceiving, "Shared holder did not reset to hidden")
        controller.startReceivingFromUser()
        try check(controller.holderShown && store.isReceiving,
                  "Starting holder mode did not show the holder")
        controller.moveHolder(to: CGPoint(x: 520, y: 280))
        let revision = controller.importRevision

        let board = NSPasteboard(name: .init("bubble-holder-drop-\(UUID().uuidString)"))
        board.clearContents()
        board.declareTypes([.string], owner: nil)
        try check(board.setString("holder drop", forType: .string),
                  "Could not prepare holder drop")
        try check(controller.receiveDrop(board, sourceProcessID: 42),
                  "Holder rejected supported manual drop")
        try check(controller.importRevision > revision,
                  "Successful holder drop did not publish importRevision")
        try check(controller.holderShown && controller.holderLocation == CGPoint(x: 520, y: 280),
                  "Successful drop moved or hid the holder")
        try check(store.items.contains(where: { $0.text == "holder drop" }),
                  "Successful holder drop was not retained")
        board.clearContents()

        controller.pauseReceiving()
        try check(!controller.holderShown && !store.isReceiving,
                  "Pausing did not hide the holder")
        try check(!store.items.isEmpty, "Pausing cleared stored content")
        controller.synchronizePersistedMode()
        try check(!controller.holderShown,
                  "Paused restore unexpectedly showed the holder")

        store.isReceiving = true
        controller.synchronizePersistedMode()
        try check(controller.holderShown && controller.holderLocation == CGPoint(x: 520, y: 280),
                  "Persisted holder restore did not retain visibility or position")
        controller.pauseReceiving()
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VerificationError(message) }
    }

    private static func sameFile(_ lhs: URL?, _ rhs: URL) -> Bool {
        lhs?.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private struct VerificationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
#endif
