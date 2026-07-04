import Foundation

/// A type-erased JSON value used for the raw JSON-Schema `Map<String, Any?>` fields on the xAI
/// request DTOs (`XAiJsonSchema.schema`, `XAiFunctionDef.parameters`).
///
/// Ports the Kotlin `Map<String, Any?>` arguments in `data/remote/XAiApi.kt` (CONVENTIONS §7
/// "Raw JSON-Schema fields → a `JSONValue`/`AnyCodable` wrapper that round-trips as a raw JSON
/// object"). Moshi serialized these maps verbatim; this enum encodes/decodes the same arbitrary
/// JSON tree so the JSON-schema payloads reach xAI unchanged.
///
/// `null` round-trips as `.null` and is **emitted** (a JSON-schema may legitimately contain
/// explicit nulls). The null-omission rule (CONVENTIONS §7) applies to *optional DTO fields* via
/// `encodeIfPresent`, not to values nested inside a schema map.
enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    /// Preserves integer-ness where possible so `"strict": true` and `"max": 30` encode without a
    /// trailing `.0`.
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    /// Bridges a Foundation JSON object (`[String: Any]` / `NSNumber` / …) into a `JSONValue` tree,
    /// distinguishing booleans and integers from doubles. Lets call sites author schemas with plain
    /// Swift literals (mirroring the Kotlin `mapOf(...)` literals).
    static func from(_ any: Any?) -> JSONValue {
        switch any {
        case nil, is NSNull:
            return .null
        case let value as Bool where isBooleanNumber(any):
            return .bool(value)
        case let value as JSONValue:
            return value
        case let value as String:
            return .string(value)
        case let value as Int:
            return .int(value)
        case let value as NSNumber:
            return fromNumber(value)
        case let value as [Any?]:
            return .array(value.map { JSONValue.from($0) })
        case let value as [String: Any?]:
            var result: [String: JSONValue] = [:]
            for (key, element) in value { result[key] = JSONValue.from(element) }
            return .object(result)
        default:
            return .null
        }
    }

    private static func isBooleanNumber(_ any: Any?) -> Bool {
        guard let number = any as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func fromNumber(_ number: NSNumber) -> JSONValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        let type = String(cString: number.objCType)
        switch type {
        case "f", "d":
            return .double(number.doubleValue)
        default:
            return .int(number.intValue)
        }
    }
}
