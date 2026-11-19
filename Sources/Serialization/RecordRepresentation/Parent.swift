import Foundation

/// A read-only reference to the record that owns this one, stored as the
/// target's `id` and saved as the record's `parent`.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @Parent(Folder.self) var folder: Folder.ID? = nil
/// }
/// ```
///
/// CloudKit shares a record together with every record whose `parent`
/// points at it, so sharing a folder shares its notes. It otherwise behaves
/// like ``Reference``: the property is set when the model is created or
/// decoded, it encodes a ``RecordRepresentation/Reference``, a `nil` parent
/// is left out of a keyed container, and a missing key decodes as `nil`.
///
/// It has no action, because CloudKit requires a parent reference to have
/// the action `.none`. A record has at most one parent, so a model declares
/// at most one `@Parent`.
@propertyWrapper
public struct Parent<Target: Identifiable>: Hashable, Sendable where Target.ID == UUID {
    public let wrappedValue: UUID?

    public init(wrappedValue: UUID? = nil, _ target: Target.Type) {
        self.wrappedValue = wrappedValue
    }
}

extension Parent: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard !container.decodeNil() else {
            self.init(Target.self)
            return
        }
        let reference = try container.decode(RecordRepresentation.Reference.self)
        guard let id = UUID(uuidString: reference.recordName) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
        }
        self.init(wrappedValue: id, Target.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString) })
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: Parent<Target>.Type, forKey key: Key) throws -> Parent<Target> {
        try decodeIfPresent(type, forKey: key) ?? Parent(Target.self)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: Parent<Target>, forKey key: Key) throws {
        guard value.wrappedValue != nil else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
