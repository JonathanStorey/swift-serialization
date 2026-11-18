import Foundation

/// A read-only to-many relationship, holding the targets' ids in order.
///
/// The initializer picks how the list is stored, and the property reads the
/// same either way:
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @References(Attachment.self) var attachments: [UUID] = []   // a field on the record
///     @References(to: \Tag.notes) var tags: [UUID] = []          // Relationship records
/// }
///
/// struct Tag: Codable, Identifiable {
///     var id: UUID
///     @References(from: Note.self, key: "tags") var notes: [UUID] = [] // the inverse
/// }
/// ```
///
/// A target type alone stores the list as one reference list field, like
/// `CKRecord`'s own. It travels with the record, and two devices settle on
/// one list.
///
/// A key path to the target's inverse stores each reference as its own
/// ``Relationship`` record, so the list has no size limit and edits from two
/// devices merge. The key path is a signal, not a name: the link is named
/// by the declaring side, as in `"Note.tags"`, from the coding key it
/// encodes. The inverse names the declaring type and that coding key, and
/// reads the same links from the other end.
///
/// The property is set when the model is created or decoded and cannot be
/// assigned afterwards. Either way it encodes each id as a
/// ``RecordRepresentation/Reference`` carrying the action. An empty list is
/// left out of a keyed container, and a missing key decodes as an empty
/// list.
///
/// The action follows `CKRecord.Reference`: with `.deleteSelf`, the record
/// holding the property deletes itself when any target is deleted. Swift
/// does not pass the attribute's arguments to `init(from:)`, so a decoded
/// list takes the action of its first element, an empty list decodes with
/// `.none`, and a decoded list does not know its storage until a schema
/// supplies it. Equality and hashing compare the ids and the action only.
@propertyWrapper
public struct References<Target: Identifiable>: Sendable where Target.ID == UUID {
    public let wrappedValue: [UUID]
    public let action: RecordRepresentation.Reference.Action

    /// How the list is stored, or `nil` when the wrapper was decoded.
    package let storage: Storage?

    package enum Storage: Hashable, Sendable {
        /// One reference list field on the record.
        case field
        /// ``Relationship`` records named by this side.
        case links
        /// ``Relationship`` records named by the declaring side, as in
        /// `"Note.tags"`.
        case inverse(String)
    }

    fileprivate init(wrappedValue: [UUID], action: RecordRepresentation.Reference.Action, storage: Storage?) {
        self.wrappedValue = wrappedValue
        self.action = action
        self.storage = storage
    }

    /// A list stored as one reference list field on the record.
    public init(wrappedValue: [UUID] = [], _ target: Target.Type, action: RecordRepresentation.Reference.Action = .none) {
        self.init(wrappedValue: wrappedValue, action: action, storage: .field)
    }

    /// A list stored as ``Relationship`` records, declared on this side.
    /// `inverse` is the target's property that reads the same links back,
    /// and its root is the target type.
    public init(wrappedValue: [UUID] = [], to inverse: KeyPath<Target, [UUID]>, action: RecordRepresentation.Reference.Action = .none) {
        self.init(wrappedValue: wrappedValue, action: action, storage: .links)
    }

    /// The inverse of the relationship that `declaringType` declares under
    /// the coding key `key`, reading the same links from the other side.
    ///
    /// The key is the coding key the declaring side encodes, which is the
    /// property name unless its `CodingKeys` rename it.
    public init(wrappedValue: [UUID] = [], from declaringType: Target.Type, key: String, action: RecordRepresentation.Reference.Action = .none) {
        self.init(wrappedValue: wrappedValue, action: action, storage: .inverse("\(Target.self).\(key)"))
    }
}

extension References: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.wrappedValue, lhs.action) == (rhs.wrappedValue, rhs.action)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
        hasher.combine(action)
    }
}

extension References {
    /// The other ends of the links to the record `source`, sorted by its
    /// side's order, `order` when it declares them and `inverseOrder` when
    /// it is an inverse, with unplaced links last.
    package init(_ links: [Relationship], from source: UUID, action: RecordRepresentation.Reference.Action = .none) {
        let order = { (link: Relationship) in (link.references[0] == source ? link.order : link.inverseOrder) ?? .max }
        let sorted = links.sorted { (order($0), $0.id.uuidString) < (order($1), $1.id.uuidString) }
        self.init(wrappedValue: sorted.map { $0.target(from: source) }, action: action, storage: nil)
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
        self.init(wrappedValue: ids, action: references.first?.action ?? .none, storage: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString, action: action) })
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: References<Target>.Type, forKey key: Key) throws -> References<Target> {
        try decodeIfPresent(type, forKey: key) ?? References(wrappedValue: [], action: .none, storage: nil)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: References<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
