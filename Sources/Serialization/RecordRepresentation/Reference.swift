import Foundation

/// A read-only reference to another `Identifiable` model, stored as the
/// target's `id`.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @Reference(to: Folder.self) var folder: Folder.ID? = nil
/// }
///
/// let note = Note(id: UUID(), folder: folder.id)
/// note.folder                      // Optional(folder.id)
/// ```
///
/// The property is set when the model is created or decoded and cannot be
/// assigned afterwards. The wrapper stores only the id. It encodes a
/// ``RecordRepresentation/Reference``, so a record encoder can tell a
/// reference from a plain `UUID`. A `nil` reference is left out of a keyed
/// container, and a missing key decodes as `nil`.
///
/// The target's `id` must be a `UUID`, and the record name is its
/// `uuidString`. That is always a valid CloudKit record name and reads back
/// exactly, which a `String` id cannot promise.
@propertyWrapper
public struct Reference<Target: Identifiable>: Hashable, Sendable where Target.ID == UUID {
    public let wrappedValue: UUID?

    public init(wrappedValue: UUID? = nil, to target: Target.Type) {
        self.wrappedValue = wrappedValue
    }
}

extension Reference: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard !container.decodeNil() else {
            self.init(to: Target.self)
            return
        }
        let reference = try container.decode(RecordRepresentation.Reference.self)
        guard let id = UUID(uuidString: reference.recordName) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
        }
        self.init(wrappedValue: id, to: Target.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(RecordRepresentation.Reference(recordName: wrappedValue.uuidString))
        } else {
            try container.encodeNil()
        }
    }
}

// Synthesized `Codable` calls these instead of the generic methods, so a
// `nil` reference behaves like an optional property: left out when encoding,
// and `nil` when its key is missing.
extension KeyedDecodingContainer {
    public func decode<Target>(_ type: Reference<Target>.Type, forKey key: Key) throws -> Reference<Target> {
        try decodeIfPresent(type, forKey: key) ?? Reference(to: Target.self)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: Reference<Target>, forKey key: Key) throws {
        guard value.wrappedValue != nil else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
