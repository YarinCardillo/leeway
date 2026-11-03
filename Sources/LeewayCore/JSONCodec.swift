import Foundation

public enum JSONCodec {
    /// Returns the v1 encoder with snake_case fields, UTC times, and stable key ordering.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Returns the v1 decoder, accepting RFC 3339 dates with optional fractional seconds.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = moment(text) else { throw CoreError.invalidRequest("invalid date") }
            return date
        }
        return decoder
    }

    /// Encodes a contract value to UTF-8 JSON. Encoding failures propagate to the caller.
    public static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder().encode(value), as: UTF8.self)
    }
}

public enum CoreError: Error, Sendable, CustomStringConvertible {
    case invalidRequest(String), storage, process, accountNotFound, server

    public var description: String {
        switch self {
        case let .invalidRequest(message): message
        case .storage: "cannot access usage history"
        case .process: "process could not run or timed out"
        case .accountNotFound: "account not found or label is ambiguous"
        case .server: "local server failed"
        }
    }
}

func moment(_ text: String) -> Date? {
    let parser = ISO8601DateFormatter()
    if let date = parser.date(from: text) { return date }
    parser.formatOptions.insert(.withFractionalSeconds)
    return parser.date(from: text)
}
