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
/// An inverse reads the same links from the other end. It names the
/// declaring type and the coding key that side encodes, so its links are
/// the declaring side's links:
///
/// ```swift
/// struct Tag: Codable, Identifiable {
///     var id: UUID
///     @References(from: Note.self, key: "tags") var notes: [UUID] = []
/// }
/// ```
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

    /// The declaring key path for an inverse, as in `"Note.tags"`, or `nil`
    /// on the declaring side. It is not encoded, so a decoded wrapper has
    /// `nil` until the schema supplies it.
    package let inverse: String?

    public init(wrappedValue: [UUID] = [], to target: Target.Type, action: RecordRepresentation.Reference.Action = .none) {
        self.wrappedValue = wrappedValue
        self.action = action
        inverse = nil
    }

    /// The inverse of the relationship that `declaringType` declares under
    /// the coding key `key`, reading the same links from the other side.
    ///
    /// The key is the coding key the declaring side encodes, which is the
    /// property name unless its `CodingKeys` rename it.
    public init(wrappedValue: [UUID] = [], from declaringType: Target.Type, key: String, action: RecordRepresentation.Reference.Action = .none) {
        self.wrappedValue = wrappedValue
        self.action = action
        inverse = "\(Target.self).\(key)"
    }
}

extension References {
    /// The other ends of the links to the record `source`, sorted by its
    /// side's order, `order` when it declares them and `inverseOrder` when
    /// it is an inverse, with unplaced links last.
    package init(_ links: [Relationship], from source: UUID, action: RecordRepresentation.Reference.Action = .none) {
        let order = { (link: Relationship) in (link.references[0] == source ? link.order : link.inverseOrder) ?? .max }
        let sorted = links.sorted { (order($0), $0.id.uuidString) < (order($1), $1.id.uuidString) }
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
