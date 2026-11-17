import Foundation

extension RecordRepresentation {
    /// One link in a many-to-many relationship, stored as a record of its own.
    ///
    /// It is an ordinary model, `Identifiable` by a `UUID` and `Codable` by
    /// synthesis, except that its ``id`` is derived rather than stored. Its
    /// `references` encode as a reference list, so CloudKit stores them as
    /// references you can follow in the Dashboard.
    ///
    /// Links are created by this package, not by clients, so the initializer
    /// has `package` access: the CloudKit target can create links, and code
    /// outside the package can only read and pass them.
    ///
    /// A link pairs two fields with the two records it joins, by position:
    /// `fields[0]` is the field on the record `references[0]`. Linking a note
    /// to a tag through `Note.tags` and `Tag.notes` gives
    /// `fields == ["notes", "tags"]` and `references == [tag.id, note.id]`.
    ///
    /// The initializer sorts the pairs by field, then id, and derives ``id``
    /// from them, so a link has the same value whichever side creates it and
    /// either side can add or remove it without knowing about the other. One
    /// query, `references CONTAINS` a record, finds every link to it.
    public struct Relationship: Codable, Hashable, Sendable, Identifiable {
        /// The two fields, paired by position with ``references``.
        public private(set) var fields: [String]
        /// The two linked records' ids, paired by position with ``fields``.
        @Related([]) public private(set) var references: [UUID]

        /// A link between `id` through `field` and `otherID` through
        /// `otherField`, given in either order.
        package init(_ field: String, _ id: UUID, _ otherField: String, _ otherID: UUID) {
            let pairs = [(field, id), (otherField, otherID)].sorted { ($0.0, $0.1.uuidString) < ($1.0, $1.1.uuidString) }
            fields = pairs.map(\.0)
            references = pairs.map(\.1)
        }

        /// The link's record name: a stable hash of both fields and both ids,
        /// so the same link always maps to the same record. It is derived, so
        /// it is never stored and can never disagree with the link.
        public var id: UUID {
            UUID(stableHashOf: (fields + references.map(\.uuidString)).joined(separator: "|"))
        }
    }
}

/// A list of ids encoded as ``RecordRepresentation/Reference`` values, like
/// ``References`` but with no target type, for
/// ``RecordRepresentation/Relationship``, whose two references point at
/// records of different types.
///
/// Only this package can create one. Clients see it only as the wrapper
/// behind `Relationship.references`.
@propertyWrapper
public struct Related: Codable, Hashable, Sendable {
    public var wrappedValue: [UUID]

    package init(_ ids: [UUID]) {
        wrappedValue = ids
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode([RecordRepresentation.Reference].self).map { reference in
            guard let id = UUID(uuidString: reference.recordName) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
            }
            return id
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString) })
    }
}
