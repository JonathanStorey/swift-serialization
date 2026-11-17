import Foundation

/// A list of references to other `Identifiable` models, stored as their
/// `id`s, for CloudKit's reference list fields.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @References(to: Tag.self) var tags: [UUID] = []
/// }
/// ```
///
/// It follows ``Reference``: target ids must be `UUID`, each element encodes
/// as a ``RecordRepresentation/Reference``, and the projected value is the
/// wrapper itself. One action applies to every element. A decoded list takes
/// the action of its first element, and an empty list decodes with `.none`.
/// An empty list is left out of a keyed container, and a missing key decodes
/// as an empty list.
@propertyWrapper
public struct References<Target>: Hashable, Sendable {
    public var wrappedValue: [UUID]
    public var action: RecordRepresentation.Reference.Action

    /// References to records of type `Target`.
    public init(wrappedValue: [UUID] = [], to target: Target.Type, action: RecordRepresentation.Reference.Action = .none) where Target: Identifiable, Target.ID == UUID {
        self.init(ids: wrappedValue, action: action)
    }

    /// References with any target type, such as `References<UUID>` for a
    /// list whose targets have different types. Internal, because Swift
    /// requires `init(wrappedValue:)` to be as visible as the wrapper.
    init(ids: [UUID] = [], action: RecordRepresentation.Reference.Action = .none) {
        self.wrappedValue = ids
        self.action = action
    }

    /// The wrapper itself, so that `$property.action` is available.
    public var projectedValue: References<Target> {
        get { self }
        set { self = newValue }
    }
}

extension References: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let references = try container.decode([RecordRepresentation.Reference].self)
        let ids = try references.map { reference in
            guard let id = UUID(uuidString: reference.recordName) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
            }
            return id
        }
        self.init(ids: ids, action: references.first?.action ?? .none)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString, action: action) })
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: References<Target>.Type, forKey key: Key) throws -> References<Target> {
        try decodeIfPresent(type, forKey: key) ?? References()
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: References<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
