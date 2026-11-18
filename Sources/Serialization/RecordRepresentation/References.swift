import Foundation

/// A read-only to-many relationship, stored as ``Relationship`` records
/// instead of a field on the record, so it has no size limit and edits from
/// two devices merge.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @References(to: Tag.self) var tags: [UUID] = []
/// }
/// ```
///
/// The property holds the targets' ids in order. It is set when the model
/// is created or decoded and cannot be assigned afterwards. The wrapper
/// stores only the ids and its action, and encodes each id as a
/// ``RecordRepresentation/Reference`` carrying the action. An empty list is
/// left out of a keyed container, and a missing key decodes as an empty
/// list.
///
/// The action follows `CKRecord.Reference`: with `.deleteSelf`, the record
/// holding the property deletes itself when any target is deleted. A
/// decoded list takes the action of its first element, and an empty list
/// decodes with `.none`, because Swift does not pass the attribute's
/// arguments to `init(from:)`.
@propertyWrapper
public struct References<Target: Identifiable>: Hashable, Sendable where Target.ID == UUID {
    public let wrappedValue: [UUID]
    public let action: RecordRepresentation.Reference.Action

    public init(wrappedValue: [UUID] = [], to target: Target.Type, action: RecordRepresentation.Reference.Action = .none) {
        self.wrappedValue = wrappedValue
        self.action = action
    }
}

extension References {
    /// The targets of the links that the record `source` declares, sorted by
    /// order, with unplaced links last.
    package init(_ links: [Relationship], from source: UUID, action: RecordRepresentation.Reference.Action = .none) {
        let sorted = links.sorted { ($0.order ?? .max, $0.id.uuidString) < ($1.order ?? .max, $1.id.uuidString) }
        self.init(wrappedValue: sorted.map { $0.target(from: source) }, to: Target.self, action: action)
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
        self.init(wrappedValue: ids, to: Target.self, action: references.first?.action ?? .none)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString, action: action) })
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: References<Target>.Type, forKey key: Key) throws -> References<Target> {
        try decodeIfPresent(type, forKey: key) ?? References(to: Target.self)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: References<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
