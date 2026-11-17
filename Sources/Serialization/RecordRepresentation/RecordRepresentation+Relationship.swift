import Foundation

extension RecordRepresentation {
    /// One link in a many-to-many relationship, stored as a record of its own.
    ///
    /// It is an ordinary model: `Identifiable` by a `UUID` and `Codable` by
    /// synthesis. Its `references` encode as a reference list, so CloudKit
    /// stores them as references you can follow in the Dashboard.
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
        /// The link's record name: a stable hash of both fields and both ids.
        public let id: UUID
        /// The two fields, paired by position with ``references``.
        public private(set) var fields: [String]
        /// The two linked records' ids, paired by position with ``fields``.
        @Related public private(set) var references: [UUID] = []

        /// A link between `id` through `field` and `otherID` through
        /// `otherField`, given in either order.
        public init(_ field: String, _ id: UUID, _ otherField: String, _ otherID: UUID) {
            let pairs = [(field, id), (otherField, otherID)].sorted { ($0.0, $0.1.uuidString) < ($1.0, $1.1.uuidString) }
            let fields = pairs.map(\.0)
            let ids = pairs.map(\.1)
            self.id = UUID(stableHashOf: (fields + ids.map(\.uuidString)).joined(separator: "|"))
            self.fields = fields
            self.references = ids
        }
    }
}

/// Encodes a list of ids as ``RecordRepresentation/Reference`` values, like
/// ``References``, for ``RecordRepresentation/Relationship``, whose two
/// references point at records of different types.
@propertyWrapper
private struct Related: Codable, Hashable, Sendable {
    var wrappedValue: [UUID]

    init(wrappedValue: [UUID]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode([RecordRepresentation.Reference].self).map { reference in
            guard let id = UUID(uuidString: reference.recordName) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
            }
            return id
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString) })
    }
}
