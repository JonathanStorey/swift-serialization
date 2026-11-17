import Foundation

extension RecordRepresentation {
    /// One link in a many-to-many relationship, stored as a record of its own.
    ///
    /// It is an ordinary model: `Identifiable` by a `UUID`, `Codable` by
    /// synthesis, and holding its links with `@References`, so CloudKit stores
    /// them as a reference list you can follow in the Dashboard.
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
        @References<UUID> public private(set) var references: [UUID] = []

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
