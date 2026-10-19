import Foundation

/// Preserves scalar tokens verbatim, including extension numbers beyond Decimal precision.
/// Lexical validation preserves arbitrary number tokens and rejects duplicate object keys.
indirect enum LosslessJSON {
    case object([String: LosslessJSON]), array([LosslessJSON]), scalar(String)
    var object: [String: LosslessJSON]? { if case let .object(v) = self { return v }; return nil }
    var array: [LosslessJSON]? { if case let .array(v) = self { return v }; return nil }
    var string: String? { if case let .scalar(v) = self { return try? JSONDecoder().decode(String.self, from: Data(v.utf8)) }; return nil }
    static func parse(_ data: Data) throws -> Self {
        var parser = Parser(bytes: Array(data))
        let result = try parser.value()
        parser.space()
        guard parser.index == parser.bytes.count else { throw CompatibleNoteFile.Failure.invalidDocument }
        return result
    }
    func data() throws -> Data { Data(try rendered().utf8) }
    private func rendered() throws -> String {
        switch self {
        case let .scalar(token): return token
        case let .array(values): return "[" + (try values.map { try $0.rendered() }.joined(separator: ",")) + "]"
        case let .object(fields):
            return "{" + (try fields.keys.sorted().map { key in
                String(decoding: try JSONEncoder().encode(key), as: UTF8.self) + ":" + (try fields[key]!.rendered())
            }.joined(separator: ",")) + "}"
        }
    }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        mutating func space() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
        mutating func token() throws -> String {
            guard index < bytes.count else { throw CompatibleNoteFile.Failure.invalidDocument }
            let start = index
            if bytes[index] == 34 {
                index += 1
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { index += 1; break }
                    index += 1
                }
            } else {
                while index < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }
            }
            guard index > start && index <= bytes.count else { throw CompatibleNoteFile.Failure.invalidDocument }
            guard let result = String(bytes: bytes[start..<index], encoding: .utf8) else { throw CompatibleNoteFile.Failure.invalidDocument }
            if bytes[start] == 34 {
                _ = try JSONDecoder().decode(String.self, from: Data(result.utf8))
            } else if !["true", "false", "null"].contains(result) {
                guard result.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw CompatibleNoteFile.Failure.invalidDocument }
            }
            return result
        }
        mutating func value(depth: Int = 0) throws -> LosslessJSON {
            guard depth < 512 else { throw CompatibleNoteFile.Failure.invalidDocument }
            space()
            guard index < bytes.count else { throw CompatibleNoteFile.Failure.invalidDocument }
            if bytes[index] == 123 {
                index += 1; space()
                var fields: [String: LosslessJSON] = [:]
                if index < bytes.count && bytes[index] == 125 { index += 1; return .object(fields) }
                while index < bytes.count {
                    space()
                    let key = try JSONDecoder().decode(String.self, from: Data(token().utf8))
                    guard fields[key] == nil else { throw CompatibleNoteFile.Failure.invalidDocument }
                    space(); guard index < bytes.count && bytes[index] == 58 else { throw CompatibleNoteFile.Failure.invalidDocument }
                    index += 1; fields[key] = try value(depth: depth + 1); space()
                    guard index < bytes.count else { throw CompatibleNoteFile.Failure.invalidDocument }
                    let delimiter = bytes[index]; index += 1
                    if delimiter == 125 { return .object(fields) }
                    guard delimiter == 44 else { throw CompatibleNoteFile.Failure.invalidDocument }
                }
            } else if bytes[index] == 91 {
                index += 1; space()
                var values: [LosslessJSON] = []
                if index < bytes.count && bytes[index] == 93 { index += 1; return .array(values) }
                while index < bytes.count {
                    values.append(try value(depth: depth + 1)); space()
                    guard index < bytes.count else { throw CompatibleNoteFile.Failure.invalidDocument }
                    let delimiter = bytes[index]; index += 1
                    if delimiter == 93 { return .array(values) }
                    guard delimiter == 44 else { throw CompatibleNoteFile.Failure.invalidDocument }
                }
            } else { return .scalar(try token()) }
            throw CompatibleNoteFile.Failure.invalidDocument
        }
    }
}
