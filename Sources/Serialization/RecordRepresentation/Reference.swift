import Foundation

/// A reference to another `Identifiable` model, stored as the target's `id`.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @Reference(to: Folder.self, action: .deleteSelf) var folder: Folder.ID? = nil
/// }
/// ```
///
/// The property reads and writes the target's `id`. The wrapper encodes a
/// ``RecordRepresentation/Reference``, so the record name and the action
/// travel together. A `nil` reference is left out of a keyed container, and a
/// missing key decodes as `nil`.
///
/// The target's `id` must be a `UUID`, and the record name is its
/// `uuidString`. That is always a valid CloudKit record name and reads back
/// exactly, which a `String` id cannot promise.
///
/// The action in the attribute applies to a new value. A decoded reference
/// keeps the action it was saved with, and a decoded `nil` reference has the
/// action `.none`, because Swift does not pass the attribute's arguments to
/// `init(from:)`. Read or change it through the projected value, as in
/// `note.$folder.action`.
@propertyWrapper
public struct Reference<Target: Identifiable>: Hashable, Sendable where Target.ID == UUID {
    public var wrappedValue: UUID?
    public var action: RecordRepresentation.Reference.Action

    public init(wrappedValue: UUID? = nil, to target: Target.Type, action: RecordRepresentation.Reference.Action = .none) {
        self.wrappedValue = wrappedValue
        self.action = action
    }

    /// The wrapper itself, so that `$property.action` is available.
    public var projectedValue: Reference<Target> {
        get { self }
        set { self = newValue }
    }
}

extension Reference: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.init(to: Target.self)
        } else {
            let reference = try container.decode(RecordRepresentation.Reference.self)
            guard let id = UUID(uuidString: reference.recordName) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
            }
            self.init(wrappedValue: id, to: Target.self, action: reference.action)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(RecordRepresentation.Reference(recordName: wrappedValue.uuidString, action: action))
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
