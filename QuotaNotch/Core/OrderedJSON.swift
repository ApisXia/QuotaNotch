// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A JSON value that keeps object key order and the original spelling of numbers.
///
/// QuotaNotch edits configuration files owned by other apps (Claude Code's settings.json,
/// Codex's hooks.json). `JSONSerialization` reorders keys and escapes `/`, which rewrites the
/// whole file. This type round-trips everything it does not touch, so an edit only changes
/// the entries QuotaNotch owns.
indirect enum OrderedJSON: Equatable, Sendable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The number exactly as written in the source.
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    // MARK: Object helpers

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.last(where: { $0.key == key })?.value
    }

    /// Replaces the value in place (keeping its position) or appends it. `nil` removes the key.
    mutating func set(_ key: String, _ value: OrderedJSON?) {
        guard case .object(var members) = self else { return }
        if let value {
            if let index = members.lastIndex(where: { $0.key == key }) {
                members[index].value = value
            } else {
                members.append((key, value))
            }
        } else {
            members.removeAll { $0.key == key }
        }
        self = .object(members)
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var arrayValue: [OrderedJSON]? { if case .array(let a) = self { return a }; return nil }
    var isObject: Bool { if case .object = self { return true }; return false }

    // MARK: Parsing

    struct ParseError: Error, Equatable { let offset: Int }

    static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: Array(data))
        parser.skipWhitespace()
        // A UTF-8 byte order mark is tolerated and dropped.
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.index = 3; parser.skipWhitespace() }
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw ParseError(offset: parser.index) }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            guard index < bytes.count, bytes[index] == byte else { throw ParseError(offset: index) }
            index += 1
        }

        mutating func literal(_ word: String) throws {
            for byte in word.utf8 { try expect(byte) }
        }

        mutating func value(depth: Int) throws -> OrderedJSON {
            guard depth < 256 else { throw ParseError(offset: index) }
            skipWhitespace()
            guard index < bytes.count else { throw ParseError(offset: index) }
            switch bytes[index] {
            case UInt8(ascii: "{"):
                index += 1
                var members: [(key: String, value: OrderedJSON)] = []
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                while true {
                    skipWhitespace()
                    let key = try string()
                    skipWhitespace()
                    try expect(UInt8(ascii: ":"))
                    let item = try value(depth: depth + 1)
                    members.append((key, item))
                    skipWhitespace()
                    guard index < bytes.count else { throw ParseError(offset: index) }
                    if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                    try expect(UInt8(ascii: "}"))
                    return .object(members)
                }
            case UInt8(ascii: "["):
                index += 1
                var items: [OrderedJSON] = []
                skipWhitespace()
                if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                while true {
                    items.append(try value(depth: depth + 1))
                    skipWhitespace()
                    guard index < bytes.count else { throw ParseError(offset: index) }
                    if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                    try expect(UInt8(ascii: "]"))
                    return .array(items)
                }
            case UInt8(ascii: "\""):
                return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default:
                return .number(try number())
            }
        }

        mutating func number() throws -> String {
            let start = index
            func digits() -> Int {
                let from = index
                while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
                return index - from
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            let intStart = index
            guard digits() > 0 else { throw ParseError(offset: start) }
            if bytes[intStart] == UInt8(ascii: "0"), index - intStart > 1 { throw ParseError(offset: start) }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw ParseError(offset: start) }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw ParseError(offset: start) }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func hex4() throws -> UInt16 {
            guard index + 4 <= bytes.count else { throw ParseError(offset: index) }
            var value: UInt16 = 0
            for _ in 0..<4 {
                let b = bytes[index]
                let digit: UInt16
                switch b {
                case 0x30...0x39: digit = UInt16(b - 0x30)
                case 0x41...0x46: digit = UInt16(b - 0x41 + 10)
                case 0x61...0x66: digit = UInt16(b - 0x61 + 10)
                default: throw ParseError(offset: index)
                }
                value = value << 4 | digit
                index += 1
            }
            return value
        }

        mutating func string() throws -> String {
            try expect(UInt8(ascii: "\""))
            var out: [UInt8] = []
            while true {
                guard index < bytes.count else { throw ParseError(offset: index) }
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    return String(decoding: out, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard index < bytes.count else { throw ParseError(offset: index) }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        var units = [try hex4()]
                        if (0xD800...0xDBFF).contains(units[0]), index + 1 < bytes.count,
                           bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            index += 2
                            units.append(try hex4())
                        }
                        out.append(contentsOf: Array(String(decoding: units, as: UTF16.self).utf8))
                    default: throw ParseError(offset: index - 1)
                    }
                case 0x00..<0x20:
                    throw ParseError(offset: index - 1)
                default:
                    out.append(byte)
                }
            }
        }
    }

    // MARK: Serialization

    /// Serializes like `JSON.stringify(value, null, indent)`, which is how Claude Code writes its settings.
    func serialized(indent: String = "  ") -> String {
        var out = ""
        write(into: &out, indent: indent, level: 0)
        return out
    }

    private func write(into out: inout String, indent: String, level: Int) {
        let pad = String(repeating: indent, count: level + 1)
        let closePad = String(repeating: indent, count: level)
        switch self {
        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (offset, member) in members.enumerated() {
                out += pad
                Self.writeString(member.key, into: &out)
                out += ": "
                member.value.write(into: &out, indent: indent, level: level + 1)
                out += offset == members.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "}"
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (offset, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indent: indent, level: level + 1)
                out += offset == items.count - 1 ? "\n" : ",\n"
            }
            out += closePad + "]"
        case .string(let s): Self.writeString(s, into: &out)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20:
                out += "\\u" + String(repeating: "0", count: 4 - String(scalar.value, radix: 16).count)
                    + String(scalar.value, radix: 16)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }

    /// The indentation unit of an existing JSON document, so edits keep the user's style.
    static func indentUnit(of data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "  " }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            if !leading.isEmpty { return String(leading) }
        }
        return "  "
    }
}
