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
/// The record name is the text of the encoded `id`: a string as it is, and a
/// number as its digits. `UUID`, `String` and integer ids all work.
///
/// The action in the attribute applies to a new value. A decoded reference
/// keeps the action it was saved with, and a decoded `nil` reference has the
/// action `.none`, because Swift does not pass the attribute's arguments to
/// `init(from:)`. Read or change it through the projected value, as in
/// `note.$folder.action`.
@propertyWrapper
public struct Reference<Target: Identifiable>: Hashable, Sendable where Target.ID: Codable & Sendable {
    public var wrappedValue: Target.ID?
    public var action: RecordRepresentation.Reference.Action

    public init(wrappedValue: Target.ID? = nil, to target: Target.Type, action: RecordRepresentation.Reference.Action = .none) {
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
            self.init(wrappedValue: try Target.ID(recordName: reference.recordName), to: Target.self, action: reference.action)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(RecordRepresentation.Reference(recordName: try wrappedValue.recordName(), action: action))
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

private extension Encodable {
    /// This value as a record name: a string as it is, and a number as its
    /// text.
    func recordName() throws -> String {
        switch try JSONRepresentation(self) {
        case .string(let text), .number(let text):
            text
        default:
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "\(type(of: self)) does not encode as a string or a number, so it cannot be a record name."))
        }
    }
}

private extension Decodable {
    /// Reads a value from a record name written by `recordName()`.
    init(recordName: String) throws {
        if let value = try? JSONRepresentation.string(recordName).decode(Self.self) {
            self = value
        } else {
            self = try JSONRepresentation.number(recordName).decode(Self.self)
        }
    }
}
