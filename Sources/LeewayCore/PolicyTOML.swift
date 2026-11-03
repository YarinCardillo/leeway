import Foundation

// The policy format uses scalar values, string arrays, tables, and arrays of tables.
// Other TOML constructs are rejected instead of silently changing user rules.
enum PolicyValue {
    case text(String), integer(Int), number(Double), boolean(Bool), strings([String])
}

typealias PolicyTable = [String: PolicyValue]

struct PolicyTOML {
    var root: PolicyTable = [:]
    var roles: PolicyTable = [:]
    var defaults: PolicyTable = [:]
    var accounts: [PolicyTable] = []
    var projects: [PolicyTable] = []
    private var section = "root"
    private var declared: Set<String> = []

    init(_ text: String) throws {
        var pending = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = Self.uncomment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            pending += line
            if let equal = pending.firstIndex(of: "=") {
                let value = pending[pending.index(after: equal)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("["), !value.hasSuffix("]") { continue }
            }
            try consume(pending)
            pending = ""
        }
        if !pending.isEmpty { throw PolicyError("unterminated policy value") }
    }

    private mutating func consume(_ line: String) throws {
        if line.hasPrefix("[") { try select(line); return }
        guard let equal = line.firstIndex(of: "=") else { throw PolicyError("expected key = value") }
        let key = line[..<equal].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw PolicyError("invalid policy key")
        }
        let value = try Self.value(String(line[line.index(after: equal)...]).trimmingCharacters(in: .whitespaces))
        switch section {
        case "root": try Self.insert(key, value, into: &root)
        case "roles": try Self.insert(key, value, into: &roles)
        case "default": try Self.insert(key, value, into: &defaults)
        case "accounts": try Self.insert(key, value, into: &accounts[accounts.count - 1])
        default: try Self.insert(key, value, into: &projects[projects.count - 1])
        }
    }

    private mutating func select(_ line: String) throws {
        switch line {
        case "[[accounts]]": accounts.append([:]); section = "accounts"
        case "[[projects]]": projects.append([:]); section = "projects"
        case "[roles]", "[default]":
            guard declared.insert(line).inserted else { throw PolicyError("duplicate policy table") }
            section = String(line.dropFirst().dropLast())
        default: throw PolicyError("unknown policy table")
        }
    }

    private static func insert(_ key: String, _ value: PolicyValue, into table: inout PolicyTable) throws {
        guard table[key] == nil else { throw PolicyError("duplicate key: \(key)") }
        table[key] = value
    }

    private static func value(_ raw: String) throws -> PolicyValue {
        if raw.hasPrefix("\"") || raw.hasPrefix("'") { return .text(try string(raw)) }
        if raw == "true" || raw == "false" { return .boolean(raw == "true") }
        if raw.hasPrefix("["), raw.hasSuffix("]") {
            let inside = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inside.isEmpty { return .strings([]) }
            let pieces = try split(inside)
            return .strings(try pieces.map(string))
        }
        if let integer = Int(raw) { return .integer(integer) }
        if let number = Double(raw), number.isFinite { return .number(number) }
        throw PolicyError("unsupported policy value")
    }

    private static func string(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 {
            let value = String(text.dropFirst().dropLast())
            guard !value.contains("'") else { throw PolicyError("invalid literal string") }
            return value
        }
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: data) else {
            throw PolicyError("invalid quoted string")
        }
        return value
    }

    private static func split(_ text: String) throws -> [String] {
        var parts: [String] = [], part = "", quote: Character?, escaped = false
        for char in text {
            if char == ",", quote == nil { parts.append(part); part = ""; continue }
            part.append(char)
            updateQuote(char, quote: &quote, escaped: &escaped)
        }
        if quote != nil { throw PolicyError("unterminated string") }
        if !part.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(part) }
        return parts
    }

    private static func uncomment(_ text: String) -> String {
        var result = "", quote: Character?, escaped = false
        for char in text {
            if char == "#", quote == nil { break }
            result.append(char)
            updateQuote(char, quote: &quote, escaped: &escaped)
        }
        return result
    }

    private static func updateQuote(_ char: Character, quote: inout Character?, escaped: inout Bool) {
        if escaped { escaped = false; return }
        if quote == "\"", char == "\\" { escaped = true; return }
        if quote == char { quote = nil }
        else if quote == nil, char == "\"" || char == "'" { quote = char }
    }
}

extension Dictionary where Key == String, Value == PolicyValue {
    func checkKeys(_ keys: Set<String>) throws {
        if let key = self.keys.sorted().first(where: { !keys.contains($0) }) {
            let guidance: String
            switch key {
            case "ceiling": guidance = "; use target_low and target_high"
            case "over_ceiling": guidance = "; use over_target"
            default: guidance = ""
            }
            throw PolicyError("unknown key: \(key)\(guidance)")
        }
    }

    func text(_ key: String, fallback: String? = nil) throws -> String {
        guard let value = self[key] else {
            if let fallback { return fallback }
            throw PolicyError("missing key: \(key)")
        }
        guard case let .text(text) = value, !text.isEmpty || key == "codex_model" else {
            throw PolicyError("\(key) must be a non-empty string")
        }
        return text
    }

    func strings(_ key: String) throws -> [String]? {
        guard let value = self[key] else { return nil }
        guard case let .strings(items) = value, items.allSatisfy({ !$0.isEmpty }) else {
            throw PolicyError("\(key) must be an array of non-empty strings")
        }
        return items
    }

    func integer(_ key: String, fallback: Int) throws -> Int {
        guard let value = self[key] else { return fallback }
        guard case let .integer(number) = value else { throw PolicyError("\(key) must be an integer") }
        return number
    }

    func bool(_ key: String, fallback: Bool) throws -> Bool {
        guard let value = self[key] else { return fallback }
        guard case let .boolean(flag) = value else { throw PolicyError("\(key) must be a boolean") }
        return flag
    }

    func percentage(_ key: String, fallback: Double) throws -> Double {
        guard let value = self[key] else { return fallback }
        let number: Double
        switch value {
        case let .integer(found): number = Double(found)
        case let .number(found): number = found
        default: throw PolicyError("\(key) must be a percentage")
        }
        guard (0...100).contains(number) else { throw PolicyError("\(key) must be from 0 to 100") }
        return number
    }
}
