import Foundation

/// A lossless, Sendable representation of arbitrary JSON values.
///
/// Character-card and lorebook formats intentionally allow namespaced extension
/// payloads. Keeping those values opaque prevents KIN from silently deleting
/// fields created by another compatible frontend during import/export.
enum PortableJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case object([String: PortableJSONValue])
    case array([PortableJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PortableJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PortableJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: PortableJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
