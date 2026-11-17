import Foundation

extension RecordRepresentation {
    /// One link in a many-to-many relationship, stored as a record of its own.
    ///
    /// A link joins two endpoints. Each endpoint is a field on a record type
    /// and the id of one record of that type, such as the `tags` field of the
    /// `Note` whose id is `n`. The relationship is the pair of fields, so
    /// `Note.tags` with `Tag.notes` is one relationship and `Note.authors`
    /// with `Person.notes` is another, even between the same records.
    ///
    /// The endpoints are kept in canonical order, sorted by record type, then
    /// field, then id. A link therefore has the same value, ``name`` and
    /// ``id`` whichever side creates it, so either side can add or remove it
    /// without knowing about the other.
    ///
    /// ```swift
    /// let link = RecordRepresentation.Relationship(
    ///     .init(recordType: "Tag", field: "notes", id: tag.id),
    ///     .init(recordType: "Note", field: "tags", id: note.id)
    /// )
    /// link.first.recordType   // "Note"
    /// link.name               // "Note.tags|Tag.notes"
    /// ```
    public struct Relationship: Hashable, Sendable, Identifiable {
        /// One side of a link.
        public struct Endpoint: Codable, Hashable, Sendable {
            /// The record type, such as `"Note"`.
            public var recordType: String
            /// The field's coding key, such as `"tags"`.
            public var field: String
            /// The id of the record on this side.
            public var id: UUID

            public init(recordType: String, field: String, id: UUID) {
                self.recordType = recordType
                self.field = field
                self.id = id
            }
        }

        /// The endpoint that sorts first.
        public let first: Endpoint
        /// The endpoint that sorts second.
        public let second: Endpoint

        /// A link between two endpoints, given in either order.
        public init(_ endpoint: Endpoint, _ other: Endpoint) {
            (first, second) = endpoint.sortsBefore(other) ? (endpoint, other) : (other, endpoint)
        }

        /// The relationship this link belongs to, such as
        /// `"Note.tags|Tag.notes"`. Every link between the same two fields
        /// shares it. Record types and fields cannot contain `.` or `|`, so
        /// the name is unambiguous.
        public var name: String {
            "\(first.recordType).\(first.field)|\(second.recordType).\(second.field)"
        }

        /// The link's record name: a stable hash of ``name`` and both ids, so
        /// the same link always maps to the same record and can be saved or
        /// deleted without a query.
        public var id: UUID {
            UUID(stableHashOf: "\(name)|\(first.id.uuidString)|\(second.id.uuidString)")
        }
    }
}

/// Encodes the two endpoints as `first` and `second`. Decoding puts them back
/// in canonical order, so a link read from anywhere keeps its identity.
extension RecordRepresentation.Relationship: Codable {
    private enum CodingKeys: String, CodingKey {
        case first, second
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(Endpoint.self, forKey: .first), try container.decode(Endpoint.self, forKey: .second))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(first, forKey: .first)
        try container.encode(second, forKey: .second)
    }
}

private extension RecordRepresentation.Relationship.Endpoint {
    func sortsBefore(_ other: Self) -> Bool {
        (recordType, field, id.uuidString) < (other.recordType, other.field, other.id.uuidString)
    }
}
