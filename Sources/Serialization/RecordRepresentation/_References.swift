import Foundation

/// A list of references to other `Identifiable` models, stored as their
/// `id`s in one CloudKit reference list field.
///
/// Retired in favor of ``References``, which stores each reference as its
/// own link record. Kept internal for reference.
///
/// ```swift
/// struct Note: Codable, Identifiable {
///     var id: UUID
///     @_References(to: Tag.self) var tags: [UUID] = []
/// }
/// ```
///
/// It follows ``Reference``: target ids must be `UUID`, each element encodes
/// as a ``RecordRepresentation/Reference``, and the projected value is the
/// wrapper itself. One action applies to every element. A decoded list takes
/// the action of its first element, and an empty list decodes with `.none`.
/// An empty list is left out of a keyed container, and a missing key decodes
/// as an empty list.
@propertyWrapper
struct _References<Target: Identifiable>: Hashable, Sendable where Target.ID == UUID {
    var wrappedValue: [UUID]
    var action: RecordRepresentation.Reference.Action

    init(wrappedValue: [UUID] = [], to target: Target.Type, action: RecordRepresentation.Reference.Action = .none) {
        self.wrappedValue = wrappedValue
        self.action = action
    }

    /// The wrapper itself, so that `$property.action` is available.
    var projectedValue: _References<Target> {
        get { self }
        set { self = newValue }
    }
}

extension _References: Codable {
    init(from decoder: any Decoder) throws {
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

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.map { RecordRepresentation.Reference(recordName: $0.uuidString, action: action) })
    }
}

extension KeyedDecodingContainer {
    func decode<Target>(_ type: _References<Target>.Type, forKey key: Key) throws -> _References<Target> {
        try decodeIfPresent(type, forKey: key) ?? _References(to: Target.self)
    }
}

extension KeyedEncodingContainer {
    mutating func encode<Target>(_ value: _References<Target>, forKey key: Key) throws {
        guard !value.wrappedValue.isEmpty else { return }
        try encodeIfPresent(Optional(value), forKey: key)
    }
}
