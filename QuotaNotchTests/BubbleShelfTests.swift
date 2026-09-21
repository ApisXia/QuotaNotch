import Foundation
import XCTest
@testable import QuotaNotchCore

final class BubbleShelfTests: XCTestCase {
    func testInsertOrdersNewestFirstAndPromotesDuplicate() {
        let older = textItem("old", date: Date(timeIntervalSince1970: 10))
        let newer = textItem("new", date: Date(timeIntervalSince1970: 20))
        let restored = BubbleShelfRules.restoring([older, newer])
        XCTAssertEqual(restored.map(\.text), ["new", "old"])

        let repeated = textItem("old", date: Date(timeIntervalSince1970: 30))
        let result = BubbleShelfRules.inserting(repeated, into: restored)
        XCTAssertEqual(result.insertion, .duplicate(older.id))
        XCTAssertEqual(result.items.map(\.id), [older.id, newer.id])
        XCTAssertEqual(result.items.first?.addedAt, repeated.addedAt)
    }

    func testRestoreKeepsUnavailableOriginalAndDropsDuplicateAndMalformedItems() {
        let missingURL = URL(fileURLWithPath: "/tmp/no-longer-here.txt")
        let missing = BubbleShelfItem(kind: .file, title: "Missing", addedAt: Date(timeIntervalSince1970: 30),
                                      resourceURL: missingURL, availability: .unavailable)
        let duplicate = BubbleShelfItem(kind: .file, title: "Same source", addedAt: Date(timeIntervalSince1970: 20),
                                        resourceURL: missingURL)
        let malformed = BubbleShelfItem(kind: .text, title: "Broken", addedAt: Date(timeIntervalSince1970: 40))

        let restored = BubbleShelfRules.restoring([duplicate, malformed, missing])

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, missing.id)
        XCTAssertEqual(restored.first?.availability, .unavailable)
        XCTAssertEqual(restored.first?.fileURL, missingURL)
    }

    func testRemovalChangesOnlyTheShelfManifestItems() {
        let original = URL(fileURLWithPath: "/tmp/original.txt")
        let file = BubbleShelfItem(kind: .file, title: "Original", resourceURL: original)
        let text = textItem("Keep")

        let result = BubbleShelfRules.removing(file.id, from: [file, text])

        XCTAssertEqual(result, [text])
        XCTAssertEqual(file.resourceURL, original)
    }

    func testManifestRoundTripsItemsForRestartRestore() throws {
        let item = textItem("Persist me", date: Date(timeIntervalSince1970: 123))
        let manifest = BubbleShelfManifest(items: [item])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(BubbleShelfManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(BubbleShelfRules.restoring(decoded.items), [item])
    }

    func testCapacityRejectsNewItemAndRetainsExistingItems() {
        let first = textItem("first", date: Date(timeIntervalSince1970: 30))
        let second = textItem("second", date: Date(timeIntervalSince1970: 20))
        let incoming = textItem("incoming", date: Date(timeIntervalSince1970: 40))

        let result = BubbleShelfRules.inserting(incoming, into: [first, second], maximumItems: 2)

        XCTAssertEqual(result.insertion, .rejected)
        XCTAssertEqual(Set(result.items.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(result.items.count, 2)
    }

    func testFailedImportIsClearlyMarkedAndDoesNotReportSuccess() {
        var result = BubbleShelfImportResult()
        result.reject("Unsupported pasteboard format.")

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(result.message?.contains("Unsupported pasteboard format.") == true)
    }

    func testURLDedupePreservesMeaningfulFragments() {
        let first = BubbleShelfItem(kind: .url, title: "First",
                                    resourceURL: URL(string: "HTTPS://Example.com/path#section-one")!)
        let same = BubbleShelfItem(kind: .url, title: "Same normalized URL",
                                   resourceURL: URL(string: "https://example.com/path#section-one")!)
        let different = BubbleShelfItem(kind: .url, title: "Different anchor",
                                        resourceURL: URL(string: "https://example.com/path#section-two")!)

        XCTAssertEqual(first.deduplicationKey, same.deduplicationKey)
        XCTAssertNotEqual(first.deduplicationKey, different.deduplicationKey)
    }

    private func textItem(_ text: String, date: Date = Date()) -> BubbleShelfItem {
        BubbleShelfItem(kind: .text, title: text, addedAt: date, text: text)
    }
}
