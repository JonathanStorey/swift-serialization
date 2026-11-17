import Foundation

/// An ordered to-many relationship stored as ``Relationship``
/// records instead of a field, so it has no size limit and no limit on
/// cascading deletes.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @References(to: Tag.self) var tags: [UUID] = []
/// }
///
/// note.$tags.append(newTag)       // a new tag, saved with the note
/// note.tags.append(existing.id)   // an existing tag, linked by id
/// note.tags.removeAll { $0 == old.id }
/// note.$tags.links                // the stored links, by order
/// ```
///
/// The property reads and writes the targets' ids in order. The wrapper
/// holds the links as they were last saved or fetched, and tracks what
/// changed since, like a `ModelContext`:
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
public struct References<Target: Identifiable & Codable> where Target.ID == UUID {
    public var wrappedValue: [UUID] {
        didSet { inserted.removeAll { !wrappedValue.contains($0.id) } }
    }

    /// New targets to create with this relationship's next save.
    public private(set) var inserted: [Target] = []

    /// The links stored at the last save or fetch, by target id.
    private var saved: [UUID: Relationship] = [:]

    public init(wrappedValue: [UUID] = [], to target: Target.Type) {
        self.wrappedValue = wrappedValue
    }

    /// The wrapper itself, so that `$property.links` and
    /// `$property.append(_:)` are available.
    public var projectedValue: References<Target> {
        get { self }
        set { self = newValue }
    }

    /// The links stored at the last save or fetch, sorted by order.
    public var links: [Relationship] {
        saved.values.sorted { $0.order < $1.order }
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

extension References {
    /// A fetched relationship, from the links that the record `source`
    /// declares, in any order.
    package init(_ links: [Relationship], from source: UUID) {
        self.init(to: Target.self)
        saved = Dictionary(links.map { ($0.target(from: source), $0) }, uniquingKeysWith: { first, _ in first })
        wrappedValue = savedIDs
    }

    /// The links to save and to delete, for the record `source` that
    /// declares this relationship at `keyPath`, as in `"Note.tags"`. Links
    /// are saved when they are new or their order changed, and the links to
    /// delete are the saved ones.
    package func changes(keyPath: String, from source: UUID) -> (save: [Relationship], delete: [Relationship]) {
        let orders = self.orders
        let save = wrappedValue.filter { saved[$0]?.order != orders[$0] }.map {
            Relationship(keyPath: keyPath, from: source, to: $0, order: orders[$0, default: 0])
        }
        let delete = removed.compactMap { saved[$0] }.sorted { $0.order < $1.order }
        return (save, delete)
    }

    /// Records the links just saved and drops the inserted targets, after a
    /// save of ``changes(keyPath:from:)`` succeeds.
    package mutating func commit(keyPath: String, from source: UUID) {
        let save = changes(keyPath: keyPath, from: source).save
        saved = saved.filter { wrappedValue.contains($0.key) }
        for link in save {
            saved[link.target(from: source)] = link
        }
        inserted = []
    }

    /// The saved target ids, by order.
    private var savedIDs: [UUID] {
        saved.sorted { $0.value.order < $1.value.order }.map(\.key)
    }

    /// The order to save each id with: its saved order while the orders
    /// still increase, or else one more than the previous id's.
    private var orders: [UUID: Int] {
        var orders: [UUID: Int] = [:]
        var previous = -1
        for id in wrappedValue {
            let order = saved[id].flatMap { $0.order > previous ? $0.order : nil } ?? previous + 1
            orders[id] = order
            previous = order
        }
        return orders
    }
}

extension References: Equatable where Target: Equatable {}
extension References: Hashable where Target: Hashable {}
extension References: Sendable where Target: Sendable {}

/// Encodes the saved links by target id under `links`, so a local copy keeps
/// them. It adds `ids` when they differ from the saved links' order and
/// `inserted` while there are new targets. A relationship that was never
/// saved encodes only its `ids`.
extension References: Codable {
    private enum CodingKeys: String, CodingKey {
        case ids, links, inserted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(to: Target.self)
        let links = try container.decodeIfPresent([String: Relationship].self, forKey: .links) ?? [:]
        saved = try Dictionary(uniqueKeysWithValues: links.map { entry in
            guard let id = UUID(uuidString: entry.key) else {
                throw DecodingError.dataCorruptedError(forKey: .links, in: container, debugDescription: "\"\(entry.key)\" is not a UUID.")
            }
            return (id, entry.value)
        })
        wrappedValue = try container.decodeIfPresent([UUID].self, forKey: .ids) ?? savedIDs
        inserted = try container.decodeIfPresent([Target].self, forKey: .inserted) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if wrappedValue != savedIDs {
            try container.encode(wrappedValue, forKey: .ids)
        }
        if !saved.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: saved.map { ($0.key.uuidString, $0.value) }), forKey: .links)
        }
        if !inserted.isEmpty {
            try container.encode(inserted, forKey: .inserted)
        }
    }
}

extension KeyedDecodingContainer {
    public func decode<Target>(_ type: References<Target>.Type, forKey key: Key) throws -> References<Target> {
        try decodeIfPresent(type, forKey: key) ?? References(to: Target.self)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<Target>(_ value: References<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty || !value.removed.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
