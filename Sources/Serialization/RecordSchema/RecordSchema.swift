import Foundation

/// The fields a `Decodable` type stores in a CloudKit record, and whether
/// two versions of the type can read each other's records.
///
/// ```swift
/// let saved = try RecordSchema(for: NoteV1.self)
/// let current = try RecordSchema(for: NoteV2.self)
///
/// current.isSuperset(of: saved)     // V2 can read every record V1 saved
/// current.isCompatible(with: saved) // both directions
/// ```
///
/// It is built from the type alone, the way ``JSONSchema/init(for:)`` is,
/// so it sees each field's coding key, its CloudKit type, whether it is
/// optional or encrypted, and the cases of an enum. `@Timestamp` and
/// `@Transient` properties are never written, so they are not fields.
/// Indexes and delete actions do not affect reading, and a decoded wrapper
/// cannot see them, so they are not part of the schema.
public struct RecordSchema: Codable, Hashable, Sendable {
    /// The record type, the type's name, as in `"Note"`.
    public var recordType: String
    /// The fields by coding key.
    public var fields: [String: Field]

    /// One field of a record.
    public struct Field: Codable, Hashable, Sendable {
        /// How CloudKit stores the field. It can never change once a
        /// record type reaches production.
        public var type: FieldType
        /// The JSON the field holds: its optionality, enum cases, and the
        /// shape of a nested value stored as bytes.
        public var schema: JSONSchema
        /// Whether CloudKit encrypts the field end to end.
        public var isEncrypted: Bool
    }

    /// A CloudKit field type, as a record type's schema names it.
    public indirect enum FieldType: Codable, Hashable, Sendable {
        case string, int64, double, timestamp, bytes, location, reference, asset
        case list(FieldType)
    }
}

extension RecordSchema {
    /// Describes the record `type` saves, by running its `init(from:)`
    /// against a recorder, as ``JSONSchema/init(for:)`` does.
    ///
    /// - `String`, `URL` and `UUID` are `STRING`, integers and `Bool` are
    ///   `INT64`, and floating-point numbers are `DOUBLE`.
    /// - `Date` is `TIMESTAMP`, `Data` is `BYTES`, ``Location`` is
    ///   `LOCATION`, `@Asset` is `ASSET`, and `@Reference`, `@Parent` and
    ///   each element of `@References` are `REFERENCE`.
    /// - An array is a `LIST`. A nested value, or a list of lists, is stored
    ///   as `BYTES`, and its ``Field/schema`` describes it. So is a list of
///   optionals, such as `[String?]`, because a CloudKit list cannot hold
///   `nil`.
    /// - Throws a `DecodingError` when `JSONSchema` cannot describe the type,
    ///   or when the type does not decode a keyed container.
    public init<T: Decodable>(for type: T.Type) throws {
        let recorded = try JSONSchema.record(type)
        guard case .object(let properties) = recorded.schema.unwrapped else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "\(T.self) does not decode a keyed container, so it is not a record."))
        }
        recordType = String(describing: T.self)
        fields = [:]
        for property in properties {
            let hints = recorded.hints[[property.key]] ?? []
            guard !hints.contains(.serverSet) else { continue }
            fields[property.key] = Field(
                type: Self.fieldType(of: property.value, at: [property.key], hints: recorded.hints),
                schema: property.value,
                isEncrypted: hints.contains(.encrypted)
            )
        }
    }

    private static func fieldType(of schema: JSONSchema, at path: [String], hints: [[String]: Set<RecordHint>]) -> FieldType {
        let here = hints[path] ?? []
        for (hint, type) in [(RecordHint.asset, FieldType.asset), (.location, .location), (.reference, .reference), (.date, .timestamp), (.data, .bytes)] where here.contains(hint) {
            return type
        }
        switch schema.unwrapped {
        case .string: return .string
        case .integer, .boolean: return .int64
        case .number: return .double
        case .array(let items):
            // CloudKit lists cannot hold nil, so a list of optionals is bytes.
            guard !items.isOptional else { return .bytes }
            let element = fieldType(of: items, at: path + [JSONRepresentation.Path.Segment.index(0).stringValue], hints: hints)
            if case .list = element { return .bytes }
            return .list(element)
        case .object, .null, .optional: return .bytes
        }
    }
}

// MARK: - Compatibility

/// Compatibility follows CloudKit as well as `JSONDecoder`:
///
/// - A field's CloudKit type and encryption must match, because CloudKit
///   never changes them, even where JSON would accept an `Int` as a
///   `Double`.
/// - A field the reader declares and the writer lacks must be optional.
/// - Fields the reader does not declare are ignored.
/// - Each field's ``Field/schema`` must accept what the other side writes,
///   so enum cases must cover what the other side can send.
///
/// Moving a `@References` list between a field and `Relationship` records
/// does not change the type, so it is not detected here. Treat it as a
/// migration.
extension RecordSchema {
    /// Whether a type with this schema can read every record written under
    /// `other`, as in `reader.isSuperset(of: writer)`.
    public func isSuperset(of other: RecordSchema) -> Bool {
        recordType == other.recordType && fields.allSatisfy { key, field in
            guard let written = other.fields[key] else { return field.schema.isOptional }
            return field.type == written.type
                && field.isEncrypted == written.isEncrypted
                && field.schema.isSuperset(of: written.schema)
        }
    }

    /// Whether every record written under this schema can be read under
    /// `other`, as in `writer.isSubset(of: reader)`.
    public func isSubset(of other: RecordSchema) -> Bool {
        other.isSuperset(of: self)
    }

    /// Whether each schema can read every record written under the other.
    public func isCompatible(with other: RecordSchema) -> Bool {
        isSuperset(of: other) && isSubset(of: other)
    }
}

// MARK: - Identity

/// A schema's `id` is computed from the schema alone, so it is the same on
/// every launch, platform and Swift version, and equal schemas share it.
extension RecordSchema: Identifiable {
    public var id: UUID {
        let lines = fields.sorted { $0.key < $1.key }.map { key, field in
            "\(key)|\(field.type)|\(field.isEncrypted)|\(field.schema.id.uuidString)"
        }
        return UUID(stableHashOf: ([recordType] + lines).joined(separator: "\n"))
    }
}

extension RecordSchema.FieldType: CustomStringConvertible {
    /// The name CloudKit's schema language uses, as in `"LIST<REFERENCE>"`.
    public var description: String {
        switch self {
        case .string: "STRING"
        case .int64: "INT64"
        case .double: "DOUBLE"
        case .timestamp: "TIMESTAMP"
        case .bytes: "BYTES"
        case .location: "LOCATION"
        case .reference: "REFERENCE"
        case .asset: "ASSET"
        case .list(let element): "LIST<\(element)>"
        }
    }
}

// MARK: - Key paths

extension RecordSchema {
    /// The link name of a reference list, `"Root.key"`, from a key path to
    /// it, such as `"Note.tags"` for `\Note.tags`.
    ///
    /// The key is the coding key `Root` decodes the property from, found by
    /// reading the key path on a placeholder `Root` whose references each
    /// have a unique record name. It needs no runtime names, so it works in
    /// stripped builds and on Linux.
    package static func name<Root: Decodable>(of keyPath: KeyPath<Root, [UUID]>) throws -> String {
        let recorded = try JSONSchema.record(Root.self)
        guard let marker = recorded.value[keyPath: keyPath].first, let key = recorded.markers[marker]?.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The key path does not lead to a reference list that \(Root.self) decodes."))
        }
        return "\(Root.self).\(key)"
    }
}

// MARK: - Hints

/// What a decoded type tells a record about the field that holds it, beyond
/// its JSON.
package enum RecordHint: Hashable, Sendable {
    case date, data, location, reference, asset, encrypted
    /// Set by the server and never written, as `@Timestamp` is.
    case serverSet

    /// The hint for `type`, or `nil` when its JSON says enough.
    init?<T>(for type: T.Type) {
        switch type {
        case is Date.Type: self = .date
        case is Data.Type: self = .data
        case let hinting as any RecordHinting.Type: self = hinting.recordHint
        default: return nil
        }
    }
}

/// A type that stands for a kind of record field.
package protocol RecordHinting {
    static var recordHint: RecordHint { get }
}

extension Location: RecordHinting {
    package static var recordHint: RecordHint { .location }
}

extension RecordRepresentation.Reference: RecordHinting {
    package static var recordHint: RecordHint { .reference }
}

extension Asset: RecordHinting {
    package static var recordHint: RecordHint { .asset }
}

extension Encrypted: RecordHinting {
    package static var recordHint: RecordHint { .encrypted }
}

extension Timestamp: RecordHinting {
    package static var recordHint: RecordHint { .serverSet }
}

extension JSONSchema {
    /// The schema without an outer optional.
    var unwrapped: JSONSchema {
        if case .optional(let wrapped) = flattened { wrapped.unwrapped } else { self }
    }
}
