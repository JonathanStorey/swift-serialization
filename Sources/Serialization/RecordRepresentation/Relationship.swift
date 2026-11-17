import Foundation

/// A to-many relationship stored as link records instead of a field, so it
/// has no size limit and no limit on cascading deletes.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @Relationship(to: Tag.self) var tags: [UUID] = []
/// }
///
/// note.$tags.append(newTag)       // a new tag, saved with the note
/// note.tags.append(existing.id)   // an existing tag, linked by id
/// note.tags.removeAll { $0 == old.id }
/// ```
///
/// The property reads and writes the targets' ids, and the wrapper tracks
/// what changed since the last save, like a `ModelContext`:
///
/// - ``inserted`` holds new targets appended through ``append(_:)``, so one
///   save can create them along with their links.
/// - ``added`` and ``removed`` are the ids linked and unlinked.
///
/// A wrapper cannot see the model that holds it, so the encoder supplies the
/// declaring key path and record when it builds the links with
/// ``changes(keyPath:from:)``.
///
/// Inserted targets are new records. Saving one that already exists on the
/// server is a conflict that the server copy wins, so a stale copy never
/// overwrites an edit. Edit an existing target by saving it directly.
@propertyWrapper
public struct Relationship<Target: Identifiable & Codable> where Target.ID == UUID {
    public var wrappedValue: [UUID] {
        didSet { inserted.removeAll { !wrappedValue.contains($0.id) } }
    }

    /// New targets to create with this relationship's next save.
    public private(set) var inserted: [Target] = []

    /// The ids linked at the last save or fetch.
    private var saved: Set<UUID> = []

    public init(wrappedValue: [UUID] = [], to target: Target.Type) {
        self.wrappedValue = wrappedValue
    }

    /// The wrapper itself, so that `$property.inserted` and
    /// `$property.append(_:)` are available.
    public var projectedValue: Relationship<Target> {
        get { self }
        set { self = newValue }
    }

    /// The ids linked since the last save.
    public var added: Set<UUID> {
        Set(wrappedValue).subtracting(saved)
    }

    /// The ids unlinked since the last save.
    public var removed: Set<UUID> {
        saved.subtracting(wrappedValue)
    }

    /// Links a new target and holds it to be created with the next save.
    /// Appending a target again replaces the held copy.
    public mutating func append(_ target: Target) {
        if !wrappedValue.contains(target.id) {
            wrappedValue.append(target.id)
        }
        inserted.removeAll { $0.id == target.id }
        inserted.append(target)
    }
}

extension Relationship {
    /// The link records to save and to delete, for the record `source` that
    /// declares this relationship at `keyPath`, as in `"Note.tags"`.
    package func changes(keyPath: String, from source: UUID) -> (added: [RecordRepresentation.Relationship], removed: [RecordRepresentation.Relationship]) {
        let link = { RecordRepresentation.Relationship(keyPath: keyPath, from: source, to: $0) }
        return (wrappedValue.filter(added.contains).map(link), removed.sorted { $0.uuidString < $1.uuidString }.map(link))
    }

    /// Marks the current ids as saved and drops the inserted targets, after
    /// a save succeeds.
    package mutating func commit() {
        saved = Set(wrappedValue)
        inserted = []
    }
}

extension Relationship: Equatable where Target: Equatable {}
extension Relationship: Hashable where Target: Hashable {}
extension Relationship: Sendable where Target: Sendable {}

/// Encodes as `{"ids": [...]}`, with `saved` and `inserted` added only while
/// there are unsaved changes, so a local copy keeps them. A decoded
/// relationship with no `saved` key is clean, as one fetched from a server is.
extension Relationship: Codable {
    private enum CodingKeys: String, CodingKey {
        case ids, saved, inserted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try container.decode([UUID].self, forKey: .ids)
        self.init(wrappedValue: ids, to: Target.self)
        saved = try container.decodeIfPresent(Set<UUID>.self, forKey: .saved) ?? Set(ids)
        inserted = try container.decodeIfPresent([Target].self, forKey: .inserted) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wrappedValue, forKey: .ids)
        if saved != Set(wrappedValue) {
            try container.encode(saved.sorted { $0.uuidString < $1.uuidString }, forKey: .saved)
        }
        if !inserted.isEmpty {
            try container.encode(inserted, forKey: .inserted)
        }
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: Relationship<Target>.Type, forKey key: Key) throws -> Relationship<Target> {
        try decodeIfPresent(type, forKey: key) ?? Relationship(to: Target.self)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: Relationship<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty || !value.removed.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
