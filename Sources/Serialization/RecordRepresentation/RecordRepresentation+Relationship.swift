import Foundation

extension RecordRepresentation {
    /// One link in a many-to-many relationship, stored as a record of its own.
    ///
    /// A link pairs two fields with the two records it joins, by position:
    /// `fields[0]` is the field on the record `references[0]`. Linking a note
    /// to a tag through `Note.tags` and `Tag.notes` gives
    /// `fields == ["notes", "tags"]` and `references == [tag.id, note.id]`.
    ///
    /// The pairs are kept sorted by field, then id, so a link has the same
    /// value and ``id`` whichever side creates it, and either side can add or
    /// remove it without knowing about the other.
    ///
    /// `references` is stored as a CloudKit reference list, so one query,
    /// `references CONTAINS` a record, finds every link to it, including
    /// links between two records of the same type.
    public struct Relationship: Hashable, Sendable, Identifiable {
        /// The two fields, paired by position with ``references``.
        public let fields: [String]
        /// The two linked records' ids, paired by position with ``fields``.
        public let references: [UUID]

        /// A link between `id` through `field` and `otherID` through
        /// `otherField`, given in either order.
        public init(_ field: String, _ id: UUID, _ otherField: String, _ otherID: UUID) {
            let pairs = [(field, id), (otherField, otherID)].sorted { ($0.0, $0.1.uuidString) < ($1.0, $1.1.uuidString) }
            fields = pairs.map(\.0)
            references = pairs.map(\.1)
        }

        /// The link's record name: a stable hash of both fields and both ids,
        /// so the same link always maps to the same record and can be saved or
        /// deleted without a query.
        public var id: UUID {
            UUID(stableHashOf: (fields + references.map(\.uuidString)).joined(separator: "|"))
        }
    }
}

/// Encodes `fields` as strings and `references` as
/// ``RecordRepresentation/Reference`` values, a reference list in CloudKit.
/// Decoding requires exactly two of each and restores the sorted order.
extension RecordRepresentation.Relationship: Codable {
    private enum CodingKeys: String, CodingKey {
        case fields, references
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fields = try container.decode([String].self, forKey: .fields)
        let references = try container.decode([RecordRepresentation.Reference].self, forKey: .references)
        guard fields.count == 2, references.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .fields, in: container, debugDescription: "A relationship needs exactly two fields and two references.")
        }
        let ids = try references.map { reference in
            guard let id = UUID(uuidString: reference.recordName) else {
                throw DecodingError.dataCorruptedError(forKey: .references, in: container, debugDescription: "Record name \"\(reference.recordName)\" is not a UUID.")
            }
            return id
        }
        self.init(fields[0], ids[0], fields[1], ids[1])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fields, forKey: .fields)
        try container.encode(references.map { RecordRepresentation.Reference(recordName: $0.uuidString) }, forKey: .references)
    }
}
