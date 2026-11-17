import Foundation

/// An ordered to-many relationship stored as link records instead of a
/// field, so it has no size limit and no limit on cascading deletes.
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
/// The property reads and writes the targets' ids in order, and the wrapper
/// tracks what changed since the last save, like a `ModelContext`:
///
/// - ``inserted`` holds new targets appended through ``append(_:)``, so one
///   save can create them along with their links.
/// - ``added`` and ``removed`` are the ids linked and unlinked.
///
/// Each link stores an integer order. A link keeps its saved order for as
/// long as the orders still increase, so a delete writes nothing but the
/// deletion, an append writes one link, and a move writes the moved link and
/// any after it that no longer sort.
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

    /// The order of each id linked at the last save or fetch.
    private var saved: [UUID: Int] = [:]

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
        Set(wrappedValue.filter { saved[$0] == nil })
    }

    /// The ids unlinked since the last save.
    public var removed: Set<UUID> {
        Set(saved.keys).subtracting(wrappedValue)
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
    /// A fetched relationship, from the links its declaring record owns,
    /// in any order.
    package init(_ links: [RecordRepresentation.Relationship]) {
        let sorted = links.sorted { $0.order < $1.order }
        self.init(wrappedValue: sorted.map { $0.references[1] }, to: Target.self)
        saved = Dictionary(sorted.map { ($0.references[1], $0.order) }, uniquingKeysWith: { first, _ in first })
    }

    /// The link records to save and to delete, for the record `source` that
    /// declares this relationship at `keyPath`, as in `"Note.tags"`. Links
    /// are saved when they are new or their order changed.
    package func changes(keyPath: String, from source: UUID) -> (save: [RecordRepresentation.Relationship], delete: [RecordRepresentation.Relationship]) {
        let orders = self.orders
        let save = wrappedValue.filter { saved[$0] != orders[$0] }.map {
            RecordRepresentation.Relationship(keyPath: keyPath, from: source, to: $0, order: orders[$0, default: 0])
        }
        let delete = removed.sorted { $0.uuidString < $1.uuidString }.map {
            RecordRepresentation.Relationship(keyPath: keyPath, from: source, to: $0, order: saved[$0, default: 0])
        }
        return (save, delete)
    }

    /// Records the orders just saved and drops the inserted targets, after a
    /// save succeeds.
    package mutating func commit() {
        saved = orders
        inserted = []
    }

    /// The order to save each id with: its saved order while the orders
    /// still increase, or else one more than the previous id's.
    private var orders: [UUID: Int] {
        var orders: [UUID: Int] = [:]
        var previous = -1
        for id in wrappedValue {
            let order = saved[id].flatMap { $0 > previous ? $0 : nil } ?? previous + 1
            orders[id] = order
            previous = order
        }
        return orders
    }
}

extension Relationship: Equatable where Target: Equatable {}
extension Relationship: Hashable where Target: Hashable {}
extension Relationship: Sendable where Target: Sendable {}

/// Encodes as `{"ids": [...]}`. It adds `saved`, each saved id's order, when
/// those differ from the ids' positions, and `inserted` while there are new
/// targets, so a local copy keeps its changes and its gaps. A decoded
/// relationship with no `saved` key is clean, ordered by position.
extension Relationship: Codable {
    private enum CodingKeys: String, CodingKey {
        case ids, saved, inserted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try container.decode([UUID].self, forKey: .ids)
        self.init(wrappedValue: ids, to: Target.self)
        if let orders = try container.decodeIfPresent([String: Int].self, forKey: .saved) {
            saved = try Dictionary(uniqueKeysWithValues: orders.map { entry in
                guard let id = UUID(uuidString: entry.key) else {
                    throw DecodingError.dataCorruptedError(forKey: .saved, in: container, debugDescription: "\"\(entry.key)\" is not a UUID.")
                }
                return (id, entry.value)
            })
        } else {
            saved = ids.positions
        }
        inserted = try container.decodeIfPresent([Target].self, forKey: .inserted) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wrappedValue, forKey: .ids)
        if saved != wrappedValue.positions {
            try container.encode(Dictionary(uniqueKeysWithValues: saved.map { ($0.key.uuidString, $0.value) }), forKey: .saved)
        }
        if !inserted.isEmpty {
            try container.encode(inserted, forKey: .inserted)
        }
    }
}

private extension Array where Element == UUID {
    /// Each id's position, the orders of a list saved with no gaps.
    var positions: [UUID: Int] {
        Dictionary(zip(self, indices), uniquingKeysWith: { first, _ in first })
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
