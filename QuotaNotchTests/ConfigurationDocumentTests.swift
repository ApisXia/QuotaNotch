import XCTest
@testable import QuotaNotchCore

final class ConfigurationDocumentTests: XCTestCase {
    /// Written the way Claude Code writes settings.json: JSON.stringify(value, null, 2).
    private let claudeSettings = """
    {
      "permissions": {
        "allow": [
          "Bash(npm run test:*)",
          "Read(/Users/me/projects/**)"
        ],
        "deny": []
      },
      "model": "opus",
      "env": {
        "MAX_THINKING_TOKENS": "1024",
        "NOTE": "quote \\" backslash \\\\ tab \\t 中文 ✓"
      },
      "cleanupPeriodDays": 30,
      "temperature": 1.0,
      "statusLine": {
        "type": "command",
        "command": "~/.claude/statusline.sh"
      },
      "hooks": {
        "Stop": [
          {
            "matcher": "",
            "hooks": []
          }
        ]
      },
      "alwaysThinkingEnabled": false,
      "apiKeyHelper": null
    }

    """

    func testRoundTripIsByteIdentical() throws {
        let data = Data(claudeSettings.utf8)
        let parsed = try OrderedJSON.parse(data)
        XCTAssertEqual(parsed.serialized() + "\n", claudeSettings)
    }

    func testInstallThenRemoveRestoresTheExactFile() throws {
        let original = Data(claudeSettings.utf8)
        let installed = try AgentHookConfiguration.updating(original, helper: "/Users/me/Library/Application Support/QuotaNotch/Activity/QuotaNotchMonitorHook",
                                                            eventDirectory: "/events", provider: .claude)
        let text = String(decoding: installed, as: UTF8.self)
        XCTAssertFalse(text.contains("\\/"), "slashes must not be escaped")
        XCTAssertTrue(text.hasPrefix("{\n  \"permissions\""), "user key order must be kept")
        XCTAssertTrue(AgentHookConfiguration.isInstalled(installed))
        // The user's empty Stop group is not ours and must survive.
        let root = try OrderedJSON.parse(installed)
        XCTAssertEqual(root["hooks"]?["Stop"]?.arrayValue?.first?["matcher"], .string(""))
        XCTAssertEqual(try AgentHookConfiguration.updating(installed, helper: nil, eventDirectory: "/events", provider: .claude), original)
    }

    func testUnchangedEditReturnsOriginalBytes() throws {
        let compact = Data(#"{"b":1,"a":{"x":[1,2]}}"#.utf8)
        XCTAssertEqual(try ConfigurationDocument.editing(compact) { _ in }, compact)
        XCTAssertEqual(try AgentHookConfiguration.updating(compact, helper: nil, eventDirectory: "/e"), compact)
    }

    func testKeepsFourSpaceIndentationAndMissingTrailingNewline() throws {
        let original = Data("{\n    \"a\": 1\n}".utf8)
        let edited = try ConfigurationDocument.editing(original) { $0.set("b", .bool(true)) }
        XCTAssertEqual(String(decoding: edited, as: UTF8.self), "{\n    \"a\": 1,\n    \"b\": true\n}")
    }

    func testNewFileGetsTwoSpacesAndNewline() throws {
        let edited = try ConfigurationDocument.editing(nil) { $0.set("a", .array([])) }
        XCTAssertEqual(String(decoding: edited, as: UTF8.self), "{\n  \"a\": []\n}\n")
    }

    func testSetReplacesInPlaceAndRemoves() throws {
        var value = try OrderedJSON.parse(Data(#"{"a":1,"b":2,"c":3}"#.utf8))
        value.set("b", .string("x"))
        value.set("a", nil)
        XCTAssertEqual(value.serialized(indent: ""), "{\n\"b\": \"x\",\n\"c\": 3\n}")
    }

    func testRejectsInvalidDocuments() {
        for text in ["broken", "[1]", "{\"a\":}", "{\"a\":1,}", "{\"a\":01}", "{\"a\":\"\u{01}\"}", "{} {}"] {
            XCTAssertThrowsError(try ConfigurationDocument.editing(Data(text.utf8)) { _ in }, text)
        }
        // A blank file is treated like a missing one.
        XCTAssertEqual(try ConfigurationDocument.editing(Data(" \n".utf8)) { _ in }, Data(" \n".utf8))
    }

    func testUnicodeEscapesDecode() throws {
        let value = try OrderedJSON.parse(Data(#"{"s":"é😀\/"}"#.utf8))
        XCTAssertEqual(value["s"], .string("é😀/"))
        XCTAssertEqual(value.serialized(indent: ""), "{\n\"s\": \"é😀/\"\n}")
    }

    func testWriterKeepsPermissionsBackupOnceAndDetectsNoChange() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("config-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let backup = dir.appendingPathComponent("backup.json")
        try Data(#"{"a":1}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        try ConfigurationFileWriter.update(file, backup: backup) { try ConfigurationDocument.editing($0) { $0.set("b", .bool(true)) } }
        try ConfigurationFileWriter.update(file, backup: backup) { try ConfigurationDocument.editing($0) { $0.set("c", .null) } }
        XCTAssertEqual(try Data(contentsOf: backup), Data(#"{"a":1}"#.utf8), "only the first original is backed up")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o644)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("quotanotch") }
        XCTAssertEqual(leftovers, [])
    }
}

final class ConfigurationWriterNoopTests: XCTestCase {
    func testRemovingFromMissingFileCreatesNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("config-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try ConfigurationFileWriter.update(file, backup: nil) {
            try AgentHookConfiguration.updating($0, helper: nil, eventDirectory: "/e", provider: .claude)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
